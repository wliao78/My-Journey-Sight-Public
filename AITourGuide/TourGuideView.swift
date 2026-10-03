import MapKit
import PhotosUI
import SwiftUI

struct GuideMessage: Identifiable {
    let id = UUID()
    let isUser: Bool
    let text: String
}

struct TourGuideView: View {
    @StateObject private var locationService = GuideLocationService()
    @StateObject private var speech = GuideSpeechInputService()
    @StateObject private var photoPlayback = GuideSpeechPlaybackService()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var photoIsSubmitted = false
    @State private var photoAnalysisID = UUID()
    @State private var isAnalyzingPhoto = false
    @State private var subject = ""
    @State private var length: GuideLength = .short
    @State private var messages: [GuideMessage] = []
    @State private var question = ""
    @FocusState private var isQuestionFocused: Bool
    @State private var photoError: String?
    @State private var attractions: [GuideAttraction] = []
    @State private var travelMode: GuideTravelMode = .walking
    @State private var recommendationsByMode: [GuideTravelMode: [GuideAttraction]] = [:]
    @State private var searchQueriesByMode: [GuideTravelMode: String] = [:]
    @State private var didAutoRecommend = false
    @State private var attractionStatus = String(localized: "正在定位…")
    @State private var loadingAttractions = false
    @State private var isAtAttractionListBottom = false
    @State private var attractionRequestID = UUID()
    @State private var lastStartedRecommendationKey: String?
    @State private var showingSettings = false
    @State private var didOfferKeySetup = false
    @State private var selectedAttraction: GuideAttraction?
    @State private var showingCamera = false
    @State private var weather = GuideWeatherSnapshot.unavailable

    var body: some View {
        NavigationStack {
            mainScreen
            .onChange(of: selectedPhoto) { _, item in
                Task { await loadPhoto(item) }
            }
            .onChange(of: speech.transcript) { _, transcript in
                if !transcript.isEmpty { question = transcript }
            }
            .task {
                if PublicDemo.enabled { await refreshAttractions(); return }
                guard locationService.location == nil else { return }
                if !didOfferKeySetup && APIKeyStore().load() == nil {
                    didOfferKeySetup = true
                    showingSettings = true
                } else {
                    locationService.request()
                }
            }
            .onChange(of: locationService.location) { _, location in
                guard location != nil else { return }
                if !didAutoRecommend {
                    didAutoRecommend = true
                    Task { await refreshAttractions() }
                }
                Task { await refreshWeather() }
            }
            .sheet(isPresented: $showingSettings, onDismiss: {
                if PublicDemo.enabled { Task { await refreshAttractions() }; return }
                if locationService.location == nil {
                    locationService.request()
                } else if attractions.isEmpty, APIKeyStore().load() != nil {
                    Task { await refreshAttractions() }
                }
            }) { GuideSettingsView() }
            .sheet(isPresented: $showingCamera) {
                GuideCameraPicker { image in
                    showingCamera = false
                    selectedPhoto = nil
                    selectedAttraction = nil
                    subject = ""
                    messages = []
                    photoData = preparedPhotoData(image)
                    photoIsSubmitted = false
                    photoAnalysisID = UUID()
                    photoPlayback.stop()
                } onCancel: {
                    showingCamera = false
                }
            }
            .alert(String(localized: "照片未能读取"), isPresented: Binding(
                get: { photoError != nil },
                set: { if !$0 { photoError = nil } }
            )) {
                Button(String(localized: "确定")) { photoError = nil }
            } message: {
                Text(photoError ?? String(localized: "请重新选择照片。"))
            }
            .navigationDestination(for: String.self) { id in
                if let attraction = attractions.first(where: { $0.id == id }) {
                    AttractionDetailView(
                        attraction: attraction,
                        travelMode: travelMode,
                        currentLocation: locationService.location,
                        messages: $messages,
                        length: $length,
                        onAppear: {
                            selectedAttraction = attraction
                            subject = attraction.name
                            Task { await explain(attraction) }
                        },
                        onDisappear: {
                            selectedAttraction = nil
                            subject = ""
                            messages = []
                            question = ""
                        },
                        onLengthChange: { Task { await explain(attraction) } }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .safeAreaInset(edge: .bottom, spacing: 0) { inputBar }
        .background { SightTheme.background }
        .foregroundStyle(.white)
        .tint(SightTheme.accent)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(String(localized: "完成")) { isQuestionFocused = false }
            }
        }
    }

    private var mainScreen: some View {
        VStack(spacing: 0) {
            statusHeader
            Picker(String(localized: "出行方式"), selection: $travelMode) {
                ForEach(GuideTravelMode.allCases) { mode in
                    Text(LocalizedStringKey(mode.rawValue)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .onChange(of: travelMode) { _, mode in
                attractions = recommendationsByMode[mode] ?? []
                if recommendationsByMode[mode] == nil {
                    Task { await refreshAttractions() }
                }
            }
            guideScrollContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { SightTheme.background }
        .toolbar(.hidden, for: .navigationBar)
        .onDisappear { photoPlayback.stop() }
    }

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(String(localized: "我的旅程 — 玩乐"))
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.13), in: Circle())
                }
                .accessibilityLabel(String(localized: "设置"))
            }
            HStack(spacing: 8) {
                Image(systemName: "location.fill")
                    .foregroundStyle(SightTheme.accent)
                Text(PublicDemo.enabled ? PublicDemo.title : locationService.placeName)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .layoutPriority(1)
                Spacer(minLength: 4)
                Image(systemName: weather.symbol)
                Text(PublicDemo.enabled ? "" : weather.summary)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Button {
                    locationService.request()
                    Task { await refreshWeather() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel(String(localized: "刷新位置和天气"))
                if !subject.isEmpty {
                    Button { reset() } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .accessibilityLabel(String(localized: "重置讲解"))
                }
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .sightPanel(radius: 18)
        .padding(.horizontal, 16)
        .padding(.top, 5)
        .padding(.bottom, 8)
    }

    @MainActor
    private func refreshWeather() async {
        guard !PublicDemo.enabled else { return }
        guard let location = locationService.location else { return }
        weather = (try? await GuideWeatherService().current(at: location)) ?? .unavailable
    }

    private var inputBar: some View {
        VStack(spacing: 6) {
            if let error = speech.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.orange)
            }
            HStack(spacing: 10) {
                Button {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        showingCamera = true
                    } else {
                        photoError = String(localized: "模拟器没有相机；请用旁边的相册按钮选择照片。")
                    }
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.title3)
                }
                .accessibilityLabel(String(localized: "拍照"))
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.title3)
                }
                .accessibilityLabel(String(localized: "从相册选择"))
                TextField(subject.isEmpty ? String(localized: "搜索附近景点") : String(localized: "想问什么？"), text: $question, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.plain)
                    .focused($isQuestionFocused)
                    .onSubmit(sendQuestion)
                Button {
                    isQuestionFocused = false
                    Task { await speech.toggle() }
                } label: {
                    Image(systemName: speech.isListening ? "stop.circle.fill" : "mic")
                        .font(.title3)
                        .foregroundStyle(speech.isListening ? .red : SightTheme.accent)
                }
                .accessibilityLabel(speech.isListening ? String(localized: "停止语音输入") : String(localized: "开始语音输入"))
                Button(action: sendQuestion) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .accessibilityLabel(String(localized: "发送文字"))
                .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(SightTheme.border))
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private var guideScrollContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if photoData != nil {
                        photoPanel
                            .id("selected-photo")
                        if photoIsSubmitted { conversationPanel }
                    }
                    attractionPanel
                    if !attractions.isEmpty && subject.isEmpty && photoData == nil {
                        Text(String(localized: "已到最后一条 · 继续上拉刷新"))
                            .font(.footnote)
                            .foregroundStyle(SightTheme.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 8)
                    }
                    if attractions.isEmpty && !photoIsSubmitted && subject.isEmpty {
                        Button(String(localized: "使用示例场景体验")) {
                            subject = String(localized: "博物馆展品示例")
                            beginExplanation()
                        }
                    }
                }
                .padding()
            }.defaultScrollAnchor(PublicLanguage.qaScrollBottom ? .bottom : .top)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                let remaining = geometry.contentSize.height - geometry.contentOffset.y - geometry.containerSize.height
                return remaining <= 12
            } action: { _, atBottom in
                isAtAttractionListBottom = atBottom
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 25).onEnded { gesture in
                    guard isAtAttractionListBottom,
                          gesture.translation.height < -65,
                          !loadingAttractions,
                          !attractions.isEmpty,
                          subject.isEmpty,
                          photoData == nil else { return }
                    Task { await refreshAttractions(force: true) }
                }
            )
            .onChange(of: photoData) { _, data in
                if data != nil {
                    withAnimation { proxy.scrollTo("selected-photo", anchor: .top) }
                }
            }
        }
    }

    private var conversationPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            if photoIsSubmitted {
                HStack {
                    Text(String(localized: "照片讲解")).font(.title2.bold())
                    Spacer()
                    if let narration = messages.last(where: {
                        !$0.isUser && !$0.text.hasPrefix(String(localized: "正在识别照片…")) && !$0.text.hasPrefix(String(localized: "照片讲解暂不可用"))
                    }) {
                        Button {
                            photoPlayback.toggle(message: narration)
                        } label: {
                            Label(photoPlayback.speakingMessageID == narration.id ? String(localized: "停止播放") : String(localized: "播放讲解"),
                                  systemImage: photoPlayback.speakingMessageID == narration.id ? "stop.circle.fill" : "speaker.wave.2.fill")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            Picker(String(localized: "讲解长度"), selection: $length) {
                ForEach(GuideLength.allCases) { option in
                    Text(LocalizedStringKey(option.rawValue)).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: length) { _, _ in
                if photoIsSubmitted {
                    regeneratePhotoExplanation()
                } else if let selectedAttraction {
                    Task { await explain(selectedAttraction) }
                } else {
                    beginExplanation()
                }
            }
            ForEach(messages) { message in
                messageBubble(message)
            }
        }
    }

    private func messageBubble(_ message: GuideMessage) -> some View {
        Text(message.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(message.isUser ? SightTheme.accent.opacity(0.22) : SightTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var attractionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(String(localized: "附近值得看"), systemImage: "mappin.and.ellipse")
                    .font(.title3.bold())
                Spacer()
                if loadingAttractions {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(String(localized: "正在更新景点推荐"))
                }
                Button(String(localized: "刷新"), systemImage: "arrow.clockwise") {
                    Task { await refreshAttractions(force: true) }
                }
                .disabled(loadingAttractions || locationService.location == nil)
            }
            if loadingAttractions && attractions.isEmpty {
                ProgressView(String(localized: "正在查找并筛选景点…"))
            } else if attractions.isEmpty {
                if APIKeyStore().load() == nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "先设置 API Key，才能获取附近景点推荐。"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button(String(localized: "设置 API Key"), systemImage: "key.fill") {
                            showingSettings = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    Text(attractionStatus == String(localized: "正在定位…") ? locationService.message : attractionStatus)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(attractions) { attraction in
                NavigationLink(value: attraction.id) {
                    VStack(alignment: .leading, spacing: 0) {
                        GuidePlaceImage(item: attraction.item)
                            .frame(height: 210)
                            .clipped()
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(attraction.name)
                                    .font(.headline)
                                    .lineLimit(1)
                                Spacer()
                                Text(PublicDemo.enabled ? PublicDemo.title : String(format: NSLocalizedString("%@ 米", comment: ""), String(describing: Int(attraction.distance))))
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                            }
                            Text(attraction.reason)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Text(String(format: NSLocalizedString("值得知道：%@", comment: ""), String(describing: attraction.highlight)))
                                .font(.subheadline)
                                .lineLimit(3)
                        }
                        .padding(14)
                    }
                    .sightPanel(radius: 20)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .sightPanel()
    }

    @MainActor
    private func refreshAttractions(force: Bool = false) async {
        if PublicDemo.enabled {
            let names = ["城市历史馆", "海滨步道", "街区公园", "艺术展厅", "老城街区", "观景花园"]
            attractions = names.enumerated().map { index, name in
                let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0)))
                item.name = NSLocalizedString(name, comment: "Fictional demo attraction")
                return GuideAttraction(id: "demo.sight.\(index)", item: item, distance: 0,
                    reason: PublicDemo.notice,
                    highlight: String(localized: "留意建筑、空间与周围的生活细节；这是虚构场景，不代表真实地点。"))
            }
            recommendationsByMode[travelMode] = attractions
            attractionStatus = PublicDemo.notice
            return
        }
        guard !loadingAttractions, let location = locationService.location else { return }
        guard APIKeyStore().load() != nil else {
            attractionStatus = String(localized: "请先在设置中填写 API Key。")
            return
        }
        let requestedMode = travelMode
        let requestedQuery = searchQueriesByMode[requestedMode] ?? ""
        let requestKey = "\(requestedMode.rawValue)|\(requestedQuery)"
        guard force || lastStartedRecommendationKey != requestKey else { return }
        lastStartedRecommendationKey = requestKey
        loadingAttractions = true
        let requestID = UUID()
        attractionRequestID = requestID
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(90))
            guard attractionRequestID == requestID, loadingAttractions else { return }
            attractionRequestID = UUID()
            loadingAttractions = false
            attractionStatus = String(localized: "查找景点超时，请点刷新重试。")
        }
        defer {
            if attractionRequestID == requestID {
                loadingAttractions = false
                if searchQueriesByMode[requestedMode] != requestedQuery ||
                    (recommendationsByMode[travelMode] == nil && travelMode != requestedMode) {
                    Task { await refreshAttractions() }
                }
            }
        }
        do {
            let updated = try await AttractionService().recommendations(near: location, mode: requestedMode, query: requestedQuery)
            guard attractionRequestID == requestID else { return }
            recommendationsByMode[requestedMode] = updated
            if travelMode == requestedMode {
                attractions = updated
            }
            attractionStatus = updated.isEmpty ? String(localized: "附近暂未找到符合要求的景点，可尝试换个说法或切换开车。") : ""
        } catch {
            guard attractionRequestID == requestID else { return }
            attractionStatus = String(format: NSLocalizedString("推荐暂不可用：%@", comment: ""), String(describing: PublicLanguage.errorDescription(error)))
        }
    }

    @MainActor
    private func explain(_ attraction: GuideAttraction) async {
        if PublicDemo.enabled {
            messages = [GuideMessage(isUser: false, text: PublicDemo.notice + "\n" + attraction.highlight)]
            return
        }
        messages = [GuideMessage(isUser: false, text: String(localized: "正在准备讲解…"))]
        do {
            let output = try await GuideAIClient().complete(
                instructions: "你是谨慎的现场导游，说话自然、简洁，只讲这个地点独有、最值得游客知道的内容和一个具体观察点。开头直接讲重点，不重复地点名称或地址，不寒暄，不自称 AI，不说套话，不罗列泛泛建议，不加追问句。禁止‘城市日常’‘周边氛围’‘文化交融’等空泛词句。短档最多 70 字，2 分钟档最多 180 字，深度档最多 350 字。只根据提供的资料写；未经核验的历史年代、人物、馆藏、开放时间不得编造。如果提供的特色不够具体，就只说‘目前没有可靠的特色资料’，不要用废话填充。",
                input: "景点：\(attraction.name)；类别：\(attraction.item.pointOfInterestCategory?.rawValue ?? "未知")；地址：\(attraction.address)；值得知道：\(attraction.highlight)；讲解长度：\(length.rawValue)。"
            )
            guard selectedAttraction?.id == attraction.id else { return }
            messages = [GuideMessage(isUser: false, text: output)]
        } catch {
            guard selectedAttraction?.id == attraction.id else { return }
            messages = [GuideMessage(isUser: false, text: String(format: NSLocalizedString("讲解暂不可用：%@", comment: ""), String(describing: PublicLanguage.errorDescription(error))))]
        }
    }

    private var photoPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let photoData, let image = UIImage(data: photoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 260)
                    .accessibilityLabel(String(localized: "选中的照片"))
            } else {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 56))
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(photoIsSubmitted ? String(localized: "已提交的照片") : String(localized: "待提交的照片"))
                    .font(.title2.bold())
                Spacer()
                if !photoIsSubmitted {
                    Button(String(localized: "提交"), systemImage: "arrow.up.circle.fill") {
                        submitPhoto()
                    }
                    .buttonStyle(.borderedProminent)
                    Button(String(localized: "移除"), systemImage: "xmark") {
                        photoData = nil
                        selectedPhoto = nil
                        photoAnalysisID = UUID()
                        isAnalyzingPhoto = false
                        photoPlayback.stop()
                    }
                }
            }
            Text(photoIsSubmitted ? (isAnalyzingPhoto ? String(localized: "正在识别照片并准备讲解…") : String(localized: "已根据照片生成讲解；不确定的细节请以现场资料为准。")) : String(localized: "点照片旁的“提交”发送给 AI 识别；底部箭头仅发送文字。"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .sightPanel()
    }

    @MainActor
    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                photoError = String(localized: "该照片格式暂不支持。")
                return
            }
            guard let prepared = preparedPhotoData(image) else {
                photoError = String(localized: "照片无法转换为可识别格式。")
                return
            }
            photoData = prepared
            photoIsSubmitted = false
            photoAnalysisID = UUID()
            selectedAttraction = nil
            subject = ""
            messages = []
            photoPlayback.stop()
        } catch {
            photoError = PublicLanguage.errorDescription(error)
        }
    }

    private func beginExplanation() {
        messages = [GuideMessage(isUser: false, text: MockGuideService.introduction(for: subject, length: length))]
        question = ""
    }

    private func preparedPhotoData(_ image: UIImage) -> Data? {
        let scale = min(1, 1600 / max(image.size.width, image.size.height))
        let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        return UIGraphicsImageRenderer(size: size).jpegData(withCompressionQuality: 0.8) { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private func analyzePhoto(_ data: Data, question: String, requestID: UUID) {
        photoPlayback.stop()
        isAnalyzingPhoto = true
        let selectedLength = length
        let lengthInstruction: String
        switch selectedLength {
        case .short:
            lengthInstruction = PublicLanguage.isChinese ? "30 秒讲解：最多 90 个汉字，只说最容易辨认的特征和一个最值得注意的细节。" : "30-second narration: at most 70 English words. Describe identifiable features and one notable detail."
        case .medium:
            lengthInstruction = PublicLanguage.isChinese ? "2 分钟讲解：约 220 至 320 个汉字，依次说可见特征、最可能的地点或对象、值得观察的细节；事实不充分时不要为了凑长度编造。" : "2-minute narration: about 220–280 English words. Cover visible features, the likely place or object, and details to notice. Never invent facts to fill the duration."
        case .deep:
            lengthInstruction = PublicLanguage.isChinese ? "深度讲解：最多 650 个汉字，分层说明外观、结构或材质、可能用途与参观观察点，明确区分照片可见事实和未经核实的推测；证据不足时可以简短。" : "In-depth narration: at most 650 English words. Explain appearance, structure or materials, possible uses and details to observe. Distinguish visible facts from unverified inference; stay brief if evidence is limited."
        }
        Task {
            do {
                let response = try await GuideAIClient().completeImage(
                    instructions: "你是中文现场导游。先根据照片可见内容判断最可能的景点、建筑或展品，再自然地讲解。若无法可靠确认具体名称，就明确说‘仅凭照片无法确认地点’，只讲确实可见的特征。不要推断照片中人物身份，也不要编造历史年代、人物或开放信息。\(lengthInstruction)",
                    input: question.isEmpty ? "请识别这张旅行照片并生成\(selectedLength.rawValue)讲解。" : "请以\(selectedLength.rawValue)的详略程度结合照片回答：\(question)",
                    jpegData: data
                )
                guard photoAnalysisID == requestID else { return }
                messages.removeAll { $0.text == String(localized: "正在识别照片…") }
                messages.append(GuideMessage(isUser: false, text: response))
            } catch {
                guard photoAnalysisID == requestID else { return }
                messages.removeAll { $0.text == String(localized: "正在识别照片…") }
                messages.append(GuideMessage(isUser: false, text: String(format: NSLocalizedString("照片讲解暂不可用：%@", comment: ""), String(describing: PublicLanguage.errorDescription(error)))))
            }
            if photoAnalysisID == requestID { isAnalyzingPhoto = false }
        }
    }

    private func sendQuestion() {
        if PublicDemo.enabled { speech.stop(); isQuestionFocused = false; attractionStatus = String(localized: "演示模式不会处理你的输入，请关闭演示模式以获取真实 AI 结果。"); return }
        let submitted = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !submitted.isEmpty else { return }
        if speech.isListening { speech.stop() }
        isQuestionFocused = false
        question = ""
        if photoIsSubmitted, let photoData {
            messages.append(GuideMessage(isUser: true, text: submitted))
            let requestID = UUID()
            photoAnalysisID = requestID
            analyzePhoto(photoData, question: submitted, requestID: requestID)
            return
        }
        if subject.isEmpty {
            searchQueriesByMode[travelMode] = submitted
            Task { await refreshAttractions(force: true) }
            return
        }
        messages.append(GuideMessage(isUser: true, text: submitted))
        if let selectedAttraction {
            Task {
                do {
                    let answer = try await GuideAIClient().complete(
                        instructions: "你是谨慎的现场导游。只根据给出的地点信息和对话回答。没有外部核验的具体历史事实要坦诚说明不确定，不要编造。回答简短，可供继续追问。",
                        input: "地点：\(selectedAttraction.name)，地址：\(selectedAttraction.address)。先前讲解：\(messages.first?.text ?? "")。用户问题：\(submitted)"
                    )
                    guard self.selectedAttraction?.id == selectedAttraction.id else { return }
                    messages.append(GuideMessage(isUser: false, text: answer))
                } catch {
                    messages.append(GuideMessage(isUser: false, text: String(format: NSLocalizedString("回答暂不可用：%@", comment: ""), String(describing: PublicLanguage.errorDescription(error)))))
                }
            }
        } else {
            messages.append(GuideMessage(isUser: false, text: MockGuideService.answer(to: submitted, about: subject)))
        }
    }

    private func submitPhoto() {
        if PublicDemo.enabled { photoError = String(localized: "演示模式不会处理你的输入，请关闭演示模式以获取真实 AI 结果。"); return }
        guard let photoData, !photoIsSubmitted else { return }
        isQuestionFocused = false
        photoIsSubmitted = true
        subject = String(localized: "照片讲解")
        messages = [GuideMessage(isUser: false, text: String(localized: "正在识别照片…"))]
        analyzePhoto(photoData, question: "", requestID: photoAnalysisID)
    }

    private func regeneratePhotoExplanation() {
        guard photoIsSubmitted, let photoData else { return }
        photoPlayback.stop()
        let requestID = UUID()
        photoAnalysisID = requestID
        messages = [GuideMessage(isUser: false, text: String(localized: "正在识别照片…"))]
        analyzePhoto(photoData, question: "", requestID: requestID)
    }

    private func reset() {
        photoPlayback.stop()
        selectedPhoto = nil
        selectedAttraction = nil
        photoData = nil
        photoIsSubmitted = false
        photoAnalysisID = UUID()
        isAnalyzingPhoto = false
        subject = ""
        messages = []
        question = ""
    }
}
#if DEBUG
@MainActor
enum PublicLocalizationQA {
    static var screen: AnyView? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-LocalizationQA"), args.indices.contains(index + 1) else { return nil }
        let route = args[index + 1]
        if route == "settings" { return AnyView(GuideSettingsView()) }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0)))
        item.name = String(localized: "城市历史馆")
        let attraction = GuideAttraction(id: "localization.demo", item: item, distance: 100,
            reason: PublicDemo.notice, highlight: PublicDemo.notice)
        return AnyView(NavigationStack {
            AttractionDetailView(attraction: attraction, travelMode: .walking, currentLocation: nil,
                messages: .constant([GuideMessage(isUser: false, text: MockGuideService.introduction(for: item.name!, length: .short))]),
                length: .constant(.short), onAppear: {}, onDisappear: {}, onLengthChange: {})
        })
    }
}
#endif
