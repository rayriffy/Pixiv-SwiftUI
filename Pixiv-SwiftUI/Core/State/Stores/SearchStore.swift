import SwiftUI
import Combine
import Observation

@MainActor
@Observable
class SearchStore {
    static let shared = SearchStore()

    var searchText: String = "" {
        didSet {
            searchTextSubject.send(searchText)
        }
    }
    var searchHistory: [SearchTag] = []
    var suggestions: [UnifiedSearchSuggestion] = []
    var trendTags: [TrendTag] = []
    var isLoadingTrendTags: Bool = false
    var recommendedSearchTags: [TrendTag] = []
    var isLoadingRecommendedTags: Bool = false
    var recommendByTagGroups: [RecommendByTagGroup] = []

    private var cancellables = Set<AnyCancellable>()
    private let searchTextSubject = PassthroughSubject<String, Never>()
    private let api = PixivAPI.shared
    private let cache = CacheManager.shared
    private let suggestionManager = SearchSuggestionManager.shared

    private let trendTagsExpiration: CacheExpiration = .hours(1)
    private let recommendedTagsExpiration: CacheExpiration = .hours(1)

    init() {
        loadSearchHistory()

        searchTextSubject
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] text in
                guard let self = self else { return }
                let trimmedText = text.trimmingCharacters(in: .whitespaces)
                if trimmedText.isEmpty {
                    self.suggestions = []
                    return
                }
                let searchWord = trimmedText.split(separator: " ").last.map(String.init) ?? trimmedText
                Task {
                    await self.fetchSuggestions(word: searchWord)
                }
            }
            .store(in: &cancellables)
    }

    func loadSearchHistory() {
        if let data = UserDefaults.standard.data(forKey: "SearchHistoryTags"),
           let history = try? JSONDecoder().decode([SearchTag].self, from: data) {
            self.searchHistory = history
        }
    }

    func saveSearchHistory() {
        if let data = try? JSONEncoder().encode(searchHistory) {
            UserDefaults.standard.set(data, forKey: "SearchHistoryTags")
        }
    }

    func addHistory(_ tag: SearchTag) {
        var tagToInsert = tag

        if let index = searchHistory.firstIndex(where: { $0.name == tag.name }) {
            let existingTag = searchHistory[index]
            // 如果新 tag 没有翻译名，但旧 tag 有，则使用旧 tag 的翻译名
            if tagToInsert.translatedName == nil && existingTag.translatedName != nil {
                tagToInsert = existingTag
            }
            searchHistory.remove(at: index)
        }

        searchHistory.insert(tagToInsert, at: 0)
        if searchHistory.count > 100 {
            searchHistory.removeLast()
        }
        saveSearchHistory()
    }

    func addHistory(_ text: String) {
        addHistory(SearchTag(name: text, translatedName: nil))
    }

    func clearHistory() {
        searchHistory = []
        saveSearchHistory()
    }

    func removeHistory(_ name: String) {
        searchHistory.removeAll { $0.name == name }
        saveSearchHistory()
    }

    func fetchTrendTags() async {
        let cacheKey = CacheManager.trendTagsKey()

        if let cached: [TrendTag] = cache.get(forKey: cacheKey) {
            print("[SearchStore] Use cached trend tags for key: \(cacheKey)")
            self.trendTags = cached
            return
        }

        guard AccountStore.shared.isLoggedIn else {
            print("[SearchStore] Skip fetching trend tags in guest mode")
            return
        }

        isLoadingTrendTags = true
        defer { isLoadingTrendTags = false }

        do {
            let tags = try await api.getIllustTrendTags()
            self.trendTags = tags
            cache.set(tags, forKey: cacheKey, expiration: trendTagsExpiration)
        } catch {
            print("Failed to fetch trend tags: \(error)")
        }
    }

    func fetchRecommendedTags(forceRefresh: Bool = false) async {
        guard AccountStore.shared.isLoggedIn else { return }

        let tagsKey = CacheManager.recommendedTagsKey()
        let groupsKey = CacheManager.recommendByTagGroupsKey()

        if !forceRefresh,
           let cachedTags: [TrendTag] = cache.get(forKey: tagsKey),
           let cachedGroups: [RecommendByTagGroup] = cache.get(forKey: groupsKey) {
            print("[SearchStore] Use cached recommended tags and groups")
            self.recommendedSearchTags = cachedTags
            self.recommendByTagGroups = cachedGroups
            return
        }

        isLoadingRecommendedTags = true
        defer { isLoadingRecommendedTags = false }

        do {
            let response = try await api.getSearchSuggestion(mode: "all")

            // 选取出推荐标签或热门标签
            var displayTags: [SuggestionTag] = []
            if let tags = response.body.recommendTags?.illust, !tags.isEmpty {
                displayTags = tags
            } else {
                displayTags = response.body.popularTags.illust
            }

            if displayTags.isEmpty && (response.body.recommendByTags?.illust.isEmpty ?? true) { return }

            // 构建索引用于快速寻找缩略图
            var thumbnailMap: [String: SuggestionThumbnail] = [:]
            if let thumbnails = response.body.thumbnails {
                for thumb in thumbnails {
                    thumbnailMap[thumb.id] = thumb
                }
            }

            // 翻译字典
            let translations = response.body.tagTranslation ?? [:]

            // 构建分组标签对象用于首页的展示 (recommendByTags)
            var newRecommendByTagGroups: [RecommendByTagGroup] = []
            if let tagGroups = response.body.recommendByTags?.illust {
                newRecommendByTagGroups = tagGroups.compactMap { tag -> RecommendByTagGroup? in
                    let illusts: [TrendTagIllust] = tag.ids.compactMap { idItem in
                        let idString: String
                        switch idItem {
                        case .string(let str): idString = str
                        case .int(let i): idString = String(i)
                        }

                        guard let thumb = thumbnailMap[idString] else { return nil }
                        return TrendTagIllust(
                            id: Int(thumb.id) ?? 0,
                            title: thumb.title,
                            imageUrls: ImageUrls(
                                squareMedium: thumb.url,
                                medium: thumb.url,
                                large: thumb.url
                            ),
                            width: nil,
                            height: nil
                        )
                    }
                    guard !illusts.isEmpty else { return nil }
                    let officialTrans = translations[tag.tag]?.zh ?? translations[tag.tag]?.en
                    let translatedName = TagTranslationService.shared.getDisplayTranslation(for: tag.tag, officialTranslation: officialTrans)
                    return RecommendByTagGroup(tag: tag.tag, translatedName: translatedName, illusts: illusts)
                }
            }
            self.recommendByTagGroups = newRecommendByTagGroups

            self.recommendedSearchTags = displayTags.compactMap { tag -> TrendTag? in
                // 找到第一个 ID 对应的插画
                guard let firstId = tag.ids.first else { return nil }
                let idString: String
                switch firstId {
                case .string(let str): idString = str
                case .int(let i): idString = String(i)
                }

                guard let thumb = thumbnailMap[idString] else { return nil }

                let officialTrans = translations[tag.tag]?.zh ?? translations[tag.tag]?.en
                let translatedName = TagTranslationService.shared.getDisplayTranslation(for: tag.tag, officialTranslation: officialTrans)

                let trendIllust = TrendTagIllust(
                    id: Int(thumb.id) ?? 0,
                    title: thumb.title,
                    imageUrls: ImageUrls(
                        squareMedium: thumb.url,
                        medium: thumb.url,
                        large: thumb.url
                    ),
                    width: nil,
                    height: nil
                )

                return TrendTag(
                    tag: tag.tag,
                    translatedName: translatedName,
                    illust: trendIllust
                )
            }

            // 缓存结果
            cache.set(self.recommendedSearchTags, forKey: tagsKey, expiration: recommendedTagsExpiration)
            cache.set(self.recommendByTagGroups, forKey: groupsKey, expiration: recommendedTagsExpiration)
        } catch {
            print("Failed to fetch recommended tags via Ajax, falling back to Trend Tags: \(error)")
            // 如果 Ajax 失败，Fallback 到普通趋势标签
            if let tags = try? await api.getIllustTrendTags() {
                self.recommendedSearchTags = tags
                cache.set(tags, forKey: tagsKey, expiration: recommendedTagsExpiration)
            }
        }
    }

    func fetchSuggestions(word: String) async {
        self.suggestions = await suggestionManager.fetchSuggestions(query: word)
    }

    func clearMemoryCache() {
        self.trendTags = []
        self.recommendedSearchTags = []
        self.suggestions = []
        print("[SearchStore] Memory cache cleared")
    }
}
