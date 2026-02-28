import SwiftUI
import Observation

@MainActor
@Observable
final class SearchResultStore {
    var illustResults: [Illusts] = []
    var userResults: [UserPreviews] = []
    var novelResults: [Novel] = []

    var isLoading: Bool = false
    var errorMessage: String?

    // 分页状态
    var illustOffset: Int = 0
    var illustLimit: Int = 30
    var illustHasMore: Bool = false
    var isLoadingMoreIllusts: Bool = false

    var userOffset: Int = 0
    var userHasMore: Bool = false
    var isLoadingMoreUsers: Bool = false

    var novelOffset: Int = 0
    var novelLimit: Int = 30
    var novelHasMore: Bool = false
    var isLoadingMoreNovels: Bool = false

    private let api = PixivAPI.shared

    func search(
        word: String,
        sort: String = "date_desc",
        bookmarkFilter: BookmarkFilterOption = .none,
        searchTarget: SearchTargetOption = .partialMatchForTags,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) async {
        self.isLoading = true
        self.errorMessage = nil
        SearchStore.shared.addHistory(word)

        self.illustOffset = 0
        self.userOffset = 0
        self.novelOffset = 0
        self.illustHasMore = false
        self.userHasMore = false
        self.novelHasMore = false

        let finalWord = word + bookmarkFilter.suffix

        do {
            let fetchedIllusts = try await api.searchIllusts(
                word: finalWord,
                searchTarget: searchTarget.rawValue,
                sort: sort,
                startDate: startDate,
                endDate: endDate,
                offset: 0,
                limit: illustLimit
            )
            let fetchedUsers = try await api.getSearchUser(word: word, offset: 0)
            let fetchedNovels = try await api.searchNovels(
                word: finalWord,
                searchTarget: searchTarget.rawValue,
                sort: sort,
                startDate: startDate,
                endDate: endDate,
                offset: 0,
                limit: novelLimit
            )

            self.illustResults = fetchedIllusts
            self.userResults = fetchedUsers
            self.novelResults = fetchedNovels

            self.illustOffset = fetchedIllusts.count
            self.illustHasMore = fetchedIllusts.count == illustLimit
            self.userOffset = fetchedUsers.count
            self.userHasMore = !fetchedUsers.isEmpty
            self.novelOffset = fetchedNovels.count
            self.novelHasMore = fetchedNovels.count == novelLimit
        } catch {
            self.errorMessage = error.localizedDescription
        }

        self.isLoading = false
    }

    /// 加载更多插画
    func loadMoreIllusts(
        word: String,
        sort: String = "date_desc",
        bookmarkFilter: BookmarkFilterOption = .none,
        searchTarget: SearchTargetOption = .partialMatchForTags,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) async {
        guard !isLoading, !isLoadingMoreIllusts, illustHasMore else { return }
        isLoadingMoreIllusts = true
        let finalWord = word + bookmarkFilter.suffix
        do {
            let more = try await api.searchIllusts(
                word: finalWord,
                searchTarget: searchTarget.rawValue,
                sort: sort,
                startDate: startDate,
                endDate: endDate,
                offset: self.illustOffset,
                limit: self.illustLimit
            )
            self.illustResults += more
            self.illustOffset += more.count
            self.illustHasMore = more.count == illustLimit
        } catch {
            print("Failed to load more illusts: \(error)")
        }
        isLoadingMoreIllusts = false
    }

    /// 加载更多用户
    func loadMoreUsers(word: String) async {
        guard !isLoading, !isLoadingMoreUsers, userHasMore else { return }
        isLoadingMoreUsers = true
        do {
            let more = try await api.getSearchUser(word: word, offset: self.userOffset)
            self.userResults += more
            self.userOffset += more.count
            self.userHasMore = !more.isEmpty
        } catch {
            print("Failed to load more users: \(error)")
        }
        isLoadingMoreUsers = false
    }

    /// 搜索小说 (带独立状态但目前都合并在一起)
    func searchNovels(
        word: String,
        sort: String = "date_desc",
        bookmarkFilter: BookmarkFilterOption = .none,
        searchTarget: SearchTargetOption = .partialMatchForTags,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        let finalWord = word + bookmarkFilter.suffix

        do {
            let fetchedNovels = try await api.searchNovels(
                word: finalWord,
                searchTarget: searchTarget.rawValue,
                sort: sort,
                startDate: startDate,
                endDate: endDate,
                offset: 0,
                limit: novelLimit
            )
            self.novelResults = fetchedNovels
            self.novelOffset = fetchedNovels.count
            self.novelHasMore = fetchedNovels.count == novelLimit
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// 加载更多小说
    func loadMoreNovels(
        word: String,
        sort: String = "date_desc",
        bookmarkFilter: BookmarkFilterOption = .none,
        searchTarget: SearchTargetOption = .partialMatchForTags,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) async {
        guard !isLoading, !isLoadingMoreNovels, novelHasMore else { return }
        isLoadingMoreNovels = true
        let finalWord = word + bookmarkFilter.suffix

        do {
            let more = try await api.searchNovels(
                word: finalWord,
                searchTarget: searchTarget.rawValue,
                sort: sort,
                startDate: startDate,
                endDate: endDate,
                offset: self.novelOffset,
                limit: self.novelLimit
            )
            self.novelResults += more
            self.novelOffset += more.count
            self.novelHasMore = more.count == novelLimit
        } catch {
            print("Failed to load more novels: \(error)")
        }
        isLoadingMoreNovels = false
    }
}
