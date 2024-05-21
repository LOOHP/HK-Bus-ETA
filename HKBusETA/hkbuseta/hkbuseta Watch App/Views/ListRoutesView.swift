//
//  ListRouteView.swift
//  hkbuseta Watch App
//
//  Created by LOOHP on 22/12/2023.
//

import SwiftUI
import shared

struct ListRoutesView: AppScreenView {
    
    @StateObject private var jointOperatedColorFraction = StateFlowObservable(stateFlow: Shared().jointOperatedColorFractionState)
    @StateObject private var lastLookupRoutes: StateFlowListObservable<LastLookupRoute>
    
    @State private var animationTick = 0
    
    let timer = Timer.publish(every: 5.5, on: .main, in: .common).autoconnect()
    
    let etaTimer = Timer.publish(every: Double(Shared().ETA_UPDATE_INTERVAL) / 1000, on: .main, in: .common).autoconnect()
    @State private var etaActive: [String: StopIndexedRouteSearchResultEntry] = [:]
    @State private var etaResults: ETAResultsContainer<NSString> = ETAResultsContainer()
    
    @Environment(\.isLuminanceReduced) var isLuminanceReduced
    @State var ambientMode = false
    
    @State var result: [StopIndexedRouteSearchResultEntry]
    @State var listType: RouteListType
    @State var showEta: Bool
    @State var recentSort: RecentSortMode
    @State var proximitySortOrigin: Coordinates?
    @State var allowAmbient: Bool
    @State var mtrSearch: String?
    
    @State var activeSortMode: RouteSortMode
    @State var sortedByMode: [RouteSortMode: [StopIndexedRouteSearchResultEntry]]
    @State var sortedResults: [StopIndexedRouteSearchResultEntry]
    
    @State var secondLineHeights: [StopIndexedRouteSearchResultEntry: CGFloat]
    
    private let appContext: AppActiveContextWatchOS
    
    init(appContext: AppActiveContextWatchOS, data: [String: Any], storage: KotlinMutableDictionary<NSString, AnyObject>) {
        self.appContext = appContext
        let rawResult = data["result"]! as! [Any]
        var casedResult: [StopIndexedRouteSearchResultEntry]
        if rawResult.isEmpty {
            casedResult = []
        } else if rawResult.first is StopIndexedRouteSearchResultEntry {
            casedResult = rawResult as! [StopIndexedRouteSearchResultEntry]
        } else {
            let a = rawResult as! [RouteSearchResultEntry]
            casedResult = a.map { StopIndexedRouteSearchResultEntry.Companion().fromRouteSearchResultEntry(resultEntry: $0) }
        }
        casedResult.removeAll(where: {
            if $0.route == nil {
                let route = registry(appContext).findRouteByKey(lookupKey: $0.routeKey, routeNumber: nil)
                if route == nil {
                    return true
                } else {
                    $0.route = route
                }
            }
            if $0.stopInfo != nil && $0.stopInfo!.data == nil {
                let stop = registry(appContext).getStopById(stopId: $0.stopInfo!.stopId)
                if stop == nil {
                    return true
                } else {
                    $0.stopInfo!.data = stop
                }
            }
            return false
        })
        casedResult.forEach {
            let route = $0.route
            let co = $0.co
            let stopInfo = $0.stopInfo
            if route != nil && stopInfo != nil {
                $0.stopInfoIndex = registry(appContext).getAllStops(routeNumber: route!.routeNumber, bound: route!.bound[co]!, co: co, gmbRegion: route!.gmbRegion).firstIndex(where: {
                    $0.stopId == stopInfo!.stopId
                })?.asInt32() ?? -1
            }
        }
        self.result = casedResult
        let listType = data["listType"] as? RouteListType ?? RouteListType.Companion().NORMAL
        self.listType = listType
        self.showEta = data["showEta"] as? Bool ?? false
        let recentSort = data["recentSort"] as? RecentSortMode ?? RecentSortMode.disabled
        self.recentSort = recentSort
        let proximitySortOrigin = data["proximitySortOrigin"] as? Coordinates
        self.proximitySortOrigin = proximitySortOrigin
        self.allowAmbient = data["allowAmbient"] as? Bool ?? false
        let activeSortMode = recentSort.forcedMode ? recentSort.defaultSortMode : {
            let preferred = Shared().routeSortModePreference[listType]
            if preferred == nil {
                return RouteSortMode.normal
            } else {
                if preferred!.isLegalMode(allowRecentSort: recentSort == RecentSortMode.choice, allowProximitySort: proximitySortOrigin != nil) {
                    return preferred!
                } else {
                    return RouteSortMode.normal
                }
            }
        }()
        self.activeSortMode = activeSortMode
        self.mtrSearch = data["mtrSearch"] as? String
        let sortedByMode = StopIndexedRouteSearchResultEntryKt.bySortModes(casedResult, context: appContext, recentSortMode: recentSort, includeFavouritesInRecent: listType != RouteListType.Companion().RECENT, proximitySortOrigin: proximitySortOrigin)
        self.sortedByMode = sortedByMode
        self.sortedResults = sortedByMode[activeSortMode]!
        self.secondLineHeights = [:]
        self._lastLookupRoutes = StateObject(wrappedValue: StateFlowListObservable(stateFlow: Shared().lastLookupRoutes, initSubscribe: listType == RouteListType.Companion().RECENT))
    }
    
    var body: some View {
        ScrollViewReader { value in
            ScrollView(.vertical) {
                LazyVStack {
                    Spacer().frame(fixedSize: 10.scaled(appContext))
                    if !ambientMode {
                        if recentSort == RecentSortMode.forced {
                            Button(action: {
                                registry(appContext).clearLastLookupRoutes(context: appContext)
                                appContext.finish()
                            }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 17.scaled(appContext, true)))
                                    .foregroundColor(.red)
                            }
                            .frame(width: 45.scaled(appContext), height: 45.scaled(appContext))
                            .clipShape(RoundedRectangle(cornerRadius: 25))
                            .ignoresSafeArea(.all)
                        } else if recentSort == RecentSortMode.choice || proximitySortOrigin != nil {
                            Button(action: {
                                activeSortMode = activeSortMode.nextMode(allowRecentSort: recentSort == RecentSortMode.choice, allowProximitySort: proximitySortOrigin != nil)
                            }) {
                                switch activeSortMode {
                                case RouteSortMode.proximity:
                                    Text(Shared().language == "en" ? "Sort: Proximity" : "排序: 巴士站距離")
                                case RouteSortMode.recent:
                                    Text(Shared().language == "en" ? "Sort: Fav/Recent" : "排序: 喜歡/最近瀏覽")
                                default:
                                    Text(Shared().language == "en" ? "Sort: Normal" : "排序: 正常")
                                }
                            }
                            .font(.system(size: 17.scaled(appContext), weight: .bold))
                            .frame(width: 170.scaled(appContext), height: 45.scaled(appContext))
                            .clipShape(RoundedRectangle(cornerRadius: 25))
                            .ignoresSafeArea(.all)
                        }
                    }
                    if let stopId = mtrSearch {
                        if stopId.isEmpty {
                            Button(action: {
                                let data = newAppDataConatiner()
                                data["type"] = "MTR"
                                appContext.startActivity(appIntent: newAppIntent(appContext, AppScreen.searchTrain, data))
                            }) {
                                Text(Shared().language == "en" ? "MTR System Map" : "港鐵路綫圖")
                            }
                            .font(.system(size: 17.scaled(appContext), weight: .bold))
                            .frame(width: 140.scaled(appContext), height: 35.scaled(appContext))
                            .clipShape(RoundedRectangle(cornerRadius: 25))
                            .background {
                                colorInt(0xFF001F50)
                                    .asColor()
                                    .clipShape(RoundedRectangle(cornerRadius: 25))
                            }
                            .ignoresSafeArea(.all)
                            Button(action: {
                                let data = newAppDataConatiner()
                                data["type"] = "LRT"
                                appContext.startActivity(appIntent: newAppIntent(appContext, AppScreen.searchTrain, data))
                            }) {
                                Text(Shared().language == "en" ? "LRT Route Map" : "輕鐵路綫圖")
                            }
                            .font(.system(size: 17.scaled(appContext), weight: .bold))
                            .frame(width: 140.scaled(appContext), height: 35.scaled(appContext))
                            .clipShape(RoundedRectangle(cornerRadius: 25))
                            .background {
                                Operator.Companion().LRT.getOperatorColor(elseColor: 0xFFFFFFFF as Int64)
                                    .asColor()
                                    .adjustBrightness(percentage: 0.7)
                                    .clipShape(RoundedRectangle(cornerRadius: 25))
                            }
                            .ignoresSafeArea(.all)
                            .padding(.vertical, 5)
                        } else {
                            if let stop = RouteExtensionsKt.asStop(stopId, context: appContext) {
                                ZStack {
                                    Text(stop.remarkedName.get(language: Shared().language).asAttributedString(defaultFontSize: 20.scaled(appContext, true)))
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding(5)
                                }
                                .background {
                                    if RouteExtensionsKt.firstCo(RouteExtensionsKt.identifyStopCo(stopId)) == Operator.Companion().LRT {
                                        Operator.Companion().LRT.getOperatorColor(elseColor: 0xFFFFFFFF as Int64).asColor()
                                    } else {
                                        colorInt(0xFF001F50).asColor()
                                    }
                                }
                                .ignoresSafeArea(.all)
                            }
                        }
                    }
                    ForEach(sortedResults, id: \.uniqueKey) { route in
                        RouteRow(route: route)
                        Divider()
                    }
                }
            }
        }
        .onDisappear {
            jointOperatedColorFraction.unsubscribe()
        }
        .onReceive(timer) { _ in
            self.animationTick += 1
        }
        .onReceive(etaTimer) { _ in
            if showEta {
                for (uniqueKey, entry) in etaActive {
                    fetchEta(appContext: appContext, stopId: entry.stopInfo!.stopId, stopIndex: entry.stopInfoIndex, co: entry.co, route: entry.route!) { etaResults.set(key: uniqueKey.asNs(), result: $0) }
                }
            }
        }
        .onChange(of: activeSortMode) { _ in
            let preferred = Shared().routeSortModePreference[listType]
            if preferred == nil || activeSortMode != preferred {
                registry(appContext).setRouteSortModePreference(context: appContext, listType: listType, sortMode: activeSortMode)
            }
            withAnimation() { () -> () in
                sortedResults = sortedByMode[activeSortMode]!
            }
        }
        .onChange(of: lastLookupRoutes.state) { _ in
            let sortedByMode = StopIndexedRouteSearchResultEntryKt.bySortModes(result, context: appContext, recentSortMode: recentSort, includeFavouritesInRecent: listType != RouteListType.Companion().RECENT, proximitySortOrigin: proximitySortOrigin)
            self.sortedByMode = sortedByMode
            withAnimation() { () -> () in
                self.sortedResults = sortedByMode[activeSortMode]!
            }
        }
        .onChange(of: isLuminanceReduced) { _ in
            ambientMode = isLuminanceReduced && allowAmbient
        }
        .onAppear {
            ambientMode = isLuminanceReduced && allowAmbient
        }
    }
    
    func RouteRow(route: StopIndexedRouteSearchResultEntry) -> some View {
        let kmbCtbJoint = route.route!.isKmbCtbJoint
        let color = operatorColor(route.co.getColor(routeNumber: route.route!.routeNumber, elseColor: 0xFFFFFFFF as Int64), Operator.Companion().CTB.getOperatorColor(elseColor: 0xFFFFFFFF as Int64), jointOperatedColorFraction.state.floatValue) { _ in kmbCtbJoint }.asColor()
        let dest = route.route!.resolvedDest(prependTo: false).get(language: Shared().language)
        let altSize = route.co == Operator.Companion().MTR && Shared().language != "en"
        let routeNumber = route.co.getListDisplayRouteNumber(routeNumber: route.route!.routeNumber, shortened: true)
        let operatorName = route.co.getDisplayFormattedName(routeNumber: route.route!.routeNumber, kmbCtbJoint: kmbCtbJoint, language: Shared().language, elseName: FormattedTextKt.asFormattedText("???", style: [].asKt()), elseColor: 0xFFFFFFFF as Int64)
        let secondLine: [AttributedString] = {
            var list: [AttributedString] = []
            if listType == RouteListType.Companion().RECENT {
                list.append(appContext.formatDateTime(localDateTime: TimeUtilsKt.toLocalDateTime(Shared().findLookupRouteTime(routeKey: route.routeKey)?.int64Value ?? 0), includeTime: true).asAttributedString())
            }
            if route.stopInfo != nil {
                let stop = route.stopInfo!.data!
                list.append((stop.name.get(language: Shared().language)).asAttributedString())
            }
            if route.co == Operator.Companion().NLB || route.co.isFerry {
                list.append((Shared().language == "en" ? "From \(route.route!.orig.en)" : "從\(route.route!.orig.zh)開出").asAttributedString(color: color.adjustBrightness(percentage: 0.75)))
            } else if route.co == Operator.Companion().KMB && routeNumber.getKMBSubsidiary() == KMBSubsidiary.sunb {
                list.append((Shared().language == "en" ? ("Sun Bus (NR\(route.route!.routeNumber))") : ("陽光巴士 (NR\(route.route!.routeNumber))")).asAttributedString(color: color.adjustBrightness(percentage: 0.75)))
            }
            return list
        }()
        
        return Button(action: {
            registry(appContext).addLastLookupRoute(routeKey: route.routeKey, context: appContext)
            if let stopId = mtrSearch {
                if !stopId.isEmpty {
                    let stops = registry(appContext).getAllStops(routeNumber: route.route!.routeNumber, bound: route.route!.bound[route.co]!, co: route.co, gmbRegion: nil)
                    let i = stops.firstIndex { $0.stopId == stopId }!
                    let stopData = stops[i]
                    let data = newAppDataConatiner()
                    data["stopId"] = stopData.stopId
                    data["co"] = route.co
                    data["index"] = i + 1
                    data["stop"] = stopData.stop
                    data["route"] = stopData.route
                    appContext.startActivity(appIntent: newAppIntent(appContext, AppScreen.eta, data))
                    return
                }
            }
            let data = newAppDataConatiner()
            data["route"] = route
            appContext.startActivity(appIntent: newAppIntent(appContext, AppScreen.listStops, data))
        }) {
            HStack(alignment: .center, spacing: 1.scaled(appContext)) {
                VStack(alignment: .leading, spacing: -3) {
                    Text(routeNumber)
                        .frame(width: altSize ? 67.5.scaled(appContext, true) : 51.scaled(appContext, true), alignment: .leading)
                        .font(.system(size: altSize ? 18.scaled(appContext, true) : 21.scaled(appContext, true)))
                        .foregroundColor(color)
                    Text(operatorName.asAttributedString(defaultFontSize: 11.scaled(appContext, true)))
                        .font(.system(size: 11.scaled(appContext, true)))
                        .foregroundColor(color)
                }
                if secondLine.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        if route.route!.shouldPrependTo() {
                            Text(RouteExtensionsKt.bilingualToPrefix.get(language: Shared().language))
                                .font(.system(size: 13.scaled(appContext, true)))
                                .foregroundColor(color)
                        }
                        UserMarqueeText(
                            text: dest,
                            font: UIFont.systemFont(ofSize: 17.scaled(appContext, true), weight: .bold),
                            marqueeStartDelay: 2,
                            marqueeAlignment: .bottomLeading
                        )
                        .foregroundColor(color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    VStack(spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            if route.route!.shouldPrependTo() {
                                Text(RouteExtensionsKt.bilingualToPrefix.get(language: Shared().language))
                                    .font(.system(size: 13.scaled(appContext, true)))
                                    .foregroundColor(color)
                            }
                            UserMarqueeText(
                                text: dest,
                                font: UIFont.systemFont(ofSize: 17.scaled(appContext, true), weight: .bold),
                                marqueeStartDelay: 2,
                                marqueeAlignment: .bottomLeading
                            )
                            .foregroundColor(color)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        CrossfadeUserMarqueeText(
                            textList: secondLine,
                            state: isLuminanceReduced ? 0 : animationTick,
                            font: UIFont.systemFont(ofSize: altSize ? 11.scaled(appContext, true) : 12.scaled(appContext, true)),
                            marqueeStartDelay: 2,
                            marqueeAlignment: .bottomLeading
                        )
                        .foregroundColor(colorInt(0xFFFFFFFF).asColor().adjustBrightness(percentage: 0.75))
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, minHeight: secondLineHeights[route] ?? 0.0, alignment: .topLeading)
                }
                if showEta {
                    ListRoutesEtaView(appContext: appContext, etaState: etaResults.getState(key: route.uniqueKey.asNs()))
                }
            }
            .contentShape(Rectangle())
        }
        .frame(width: 170.scaled(appContext))
        .frame(minHeight: 37.scaled(appContext, true))
        .buttonStyle(PlainButtonStyle())
        .transition(AnyTransition.scale)
        .onAppear {
            if kmbCtbJoint {
                jointOperatedColorFraction.subscribe()
            }
        }
        .onAppear {
            if showEta {
                etaActive[route.uniqueKey] = route
                fetchEta(appContext: appContext, stopId: route.stopInfo!.stopId, stopIndex: route.stopInfoIndex, co: route.co, route: route.route!) { etaResults.set(key: route.uniqueKey.asNs(), result: $0) }
            }
        }
        .onDisappear {
            etaActive.removeValue(forKey: route.uniqueKey)
        }
    }
}

struct ListRoutesEtaView: View {
    
    @StateObject private var etaState: StateFlowNullableObservable<Registry.ETAQueryResult>
    
    private let appContext: AppActiveContextWatchOS
    
    init(appContext: AppActiveContextWatchOS, etaState: ETAResultsState) {
        self.appContext = appContext
        self._etaState = StateObject(wrappedValue: StateFlowNullableObservable(stateFlow: etaState.state))
    }
    
    var body: some View {
        ZStack {
            let optEta = etaState.state
            if optEta != nil {
                let eta = optEta!
                if !eta.isConnectionError {
                    if !(0..<60).contains(eta.nextScheduledBus) {
                        if eta.isMtrEndOfLine {
                            Image(systemName: "arrow.forward.to.line.circle")
                                .font(.system(size: 17.scaled(appContext, true)))
                                .foregroundColor(colorInt(0xFF92C6F0).asColor())
                        } else if (eta.isTyphoonSchedule) {
                            Image(systemName: "hurricane")
                                .font(.system(size: 17.scaled(appContext, true)))
                                .foregroundColor(colorInt(0xFF92C6F0).asColor())
                        } else {
                            Image(systemName: "clock")
                                .font(.system(size: 17.scaled(appContext, true)))
                                .foregroundColor(colorInt(0xFF92C6F0).asColor())
                        }
                    } else {
                        let text: AttributedString = {
                            if (Shared().etaDisplayMode.shortTextClockTime) {
                                let text1 = Shared().getResolvedText(eta, seq: 1.asInt32(), etaDisplayMode: Shared().etaDisplayMode, context: appContext).resolvedClockTime.string.trimmingCharacters(in: .whitespaces)
                                return text1.replace("\\s+", "\n").asAttributedString(fontSize: 14.5.scaled(appContext, true))
                            } else {
                                let shortText = eta.firstLine.shortText
                                let text1 = shortText.first
                                let text2 = "\n" + shortText.second
                                return text1.asAttributedString(fontSize: 17.scaled(appContext, true)) + text2.asAttributedString(fontSize: 8.scaled(appContext, true))
                            }
                        }()
                        Text(text)
                            .multilineTextAlignment(.trailing)
                            .lineSpacing(0)
                            .frame(alignment: .trailing)
                            .foregroundColor(colorInt(0xFF92C6F0).asColor())
                    }
                }
            }
        }
        .frame(minWidth: 27.scaled(appContext, true), alignment: .trailing)
        .onAppear {
            etaState.subscribe()
        }
        .onDisappear {
            etaState.unsubscribe()
        }
    }
    
}
