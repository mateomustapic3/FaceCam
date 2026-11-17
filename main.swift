import AppKit
import AVFoundation


enum PanelShape: String, CaseIterable {
    case square = "Kvadrat"
    case rectangle = "Pravokutnik"
    case circle = "Krug"
    case rounded = "Zaobljeni pravokutnik"

    var aspect: CGFloat {
        switch self {
        case .square, .circle: return 1
        case .rectangle, .rounded: return 16.0 / 9.0
        }
    }

    func cornerRadius(for size: NSSize) -> CGFloat {
        switch self {
        case .square, .rectangle: return 0
        case .circle: return min(size.width, size.height) / 2
        case .rounded: return min(size.width, size.height) * 0.16
        }
    }
}


enum Quality: String, CaseIterable {
    case normal = "Normal"
    case economy = "Economy"

    var preset: AVCaptureSession.Preset {
        switch self {
        case .normal: return .medium    // ~480p
        case .economy: return .low      // ~352x288
        }
    }
}


final class CamPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}


final class PreviewView: NSView {
    weak var controller: AppDelegate?
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func makeBackingLayer() -> CALayer { AVCaptureVideoPreviewLayer() }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }

    override func scrollWheel(with event: NSEvent) {
        controller?.resize(by: event.scrollingDeltaY * 2)
    }
    override func magnify(with event: NSEvent) {
        guard let w = window?.frame.width else { return }
        controller?.resize(by: w * event.magnification)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = controller?.makeMenu() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func layout() {
        super.layout()
        previewLayer.cornerRadius = controller?.shape.cornerRadius(for: bounds.size) ?? 0
    }
}


final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let session = AVCaptureSession()
    let sessionQueue = DispatchQueue(label: "facecam.session", qos: .utility)
    var panel: CamPanel!
    var view: PreviewView!
    var statusItem: NSStatusItem!
    var shape: PanelShape = .circle
    var mirrored = true
    var quality: Quality = .normal
    var cameraDevice: AVCaptureDevice?
    var running = false

    let minWidth: CGFloat = 120
    let maxWidth: CGFloat = 1000

    func applicationDidFinishLaunching(_ notification: Notification) {
        let d = UserDefaults.standard
        if let s = d.string(forKey: "shape"), let sh = PanelShape(rawValue: s) { shape = sh }
        if d.object(forKey: "mirrored") != nil { mirrored = d.bool(forKey: "mirrored") }
        if let q = d.string(forKey: "quality"), let qq = Quality(rawValue: q) { quality = qq }

        setupPanel()
        setupStatusItem()
        setupPowerObservers()

        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                if granted { self.configureCamera(); self.startCamera() }
                else { self.showPermissionAlert() }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        UserDefaults.standard.set(shape.rawValue, forKey: "shape")
        UserDefaults.standard.set(mirrored, forKey: "mirrored")
        UserDefaults.standard.set(quality.rawValue, forKey: "quality")
    }


    func setupPanel() {
        let w: CGFloat = 240
        let rect = NSRect(x: 100, y: 100, width: w, height: w / shape.aspect)
        panel = CamPanel(contentRect: rect,
                         styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver                       
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.setFrameAutosaveName("FaceCamPanel")       

        view = PreviewView(frame: NSRect(origin: .zero, size: rect.size))
        view.controller = self
        panel.contentView = view

        applyShape(shape)
        panel.orderFrontRegardless()
    }

    func applyShape(_ newShape: PanelShape) {
        shape = newShape
        var f = panel.frame
        let center = NSPoint(x: f.midX, y: f.midY)
        let w = min(max(f.width, minWidth), maxWidth)
        f.size = NSSize(width: w, height: w / shape.aspect)
        f.origin = NSPoint(x: center.x - f.width / 2, y: center.y - f.height / 2)
        panel.setFrame(f, display: true)
        view.needsLayout = true
        UserDefaults.standard.set(shape.rawValue, forKey: "shape")
    }

    func resize(by delta: CGFloat) {
        var f = panel.frame
        let center = NSPoint(x: f.midX, y: f.midY)
        let w = min(max(f.width + delta, minWidth), maxWidth)
        f.size = NSSize(width: w, height: w / shape.aspect)
        f.origin = NSPoint(x: center.x - f.width / 2, y: center.y - f.height / 2)
        panel.setFrame(f, display: true)
    }

    func setWidth(_ w: CGFloat) { resize(by: w - panel.frame.width) }


    func configureCamera() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        cameraDevice = device

        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input) }
        session.commitConfiguration()
        applyQuality(quality)

        view.previewLayer.session = session
        applyMirror()
    }

    func applyQuality(_ q: Quality) {
        quality = q
        UserDefaults.standard.set(q.rawValue, forKey: "quality")
        guard cameraDevice != nil else { return }

        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            if self.session.canSetSessionPreset(q.preset) {
                self.session.sessionPreset = q.preset
            }
            self.session.commitConfiguration()
            self.limitFrameRate()   
        }
    }

    func limitFrameRate() {
        guard let device = cameraDevice,
              let range = device.activeFormat.videoSupportedFrameRateRanges.first,
              range.minFrameRate <= 30, range.maxFrameRate >= 30,
              (try? device.lockForConfiguration()) != nil else { return }
        device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
        device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
        device.unlockForConfiguration()
    }

    func applyMirror() {
        guard let c = view.previewLayer.connection, c.isVideoMirroringSupported else { return }
        c.automaticallyAdjustsVideoMirroring = false
        c.isVideoMirrored = mirrored
    }

    func startCamera() {
        guard !running else { return }
        running = true
        sessionQueue.async { [session] in if !session.isRunning { session.startRunning() } }
    }

    func stopCamera() {
        guard running else { return }
        running = false
        sessionQueue.async { [session] in if session.isRunning { session.stopRunning() } }
    }

    func showPermissionAlert() {
        let a = NSAlert()
        a.messageText = "Nema dozvole za kameru"
        a.informativeText = "Uključi je u Postavke sustava → Privatnost i sigurnost → Kamera."
        a.runModal()
    }


    func setupPowerObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        for n in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            nc.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in self?.stopCamera() }
        }
        for n in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            nc.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in
                if self?.panel.isVisible == true { self?.startCamera() }
            }
        }
    }

    func toggleVisible() {
        if panel.isVisible {
            panel.orderOut(nil)
            stopCamera()
        } else {
            panel.orderFrontRegardless()
            startCamera()
        }
    }


    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "video.circle", accessibilityDescription: "FaceCam")
        statusItem.menu = makeMenu()
    }

    func makeMenu() -> NSMenu {
        let m = NSMenu()
        m.delegate = self
        fill(m)
        return m
    }

    func menuNeedsUpdate(_ menu: NSMenu) { fill(menu) }

    func fill(_ m: NSMenu) {
        m.removeAllItems()

        m.addItem(withTitle: panel.isVisible ? "Sakrij kameru" : "Prikaži kameru",
                  action: #selector(toggleAction), keyEquivalent: "").target = self
        m.addItem(.separator())

        for s in PanelShape.allCases {
            let i = NSMenuItem(title: s.rawValue, action: #selector(shapeAction(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = s.rawValue
            i.state = (s == shape) ? .on : .off
            m.addItem(i)
        }
        m.addItem(.separator())

        for (title, w) in [("Mala", 160), ("Srednja", 240), ("Velika", 400), ("Vrlo velika", 640)] {
            let i = NSMenuItem(title: title, action: #selector(sizeAction(_:)), keyEquivalent: "")
            i.target = self
            i.tag = w
            m.addItem(i)
        }
        m.addItem(.separator())

        for q in Quality.allCases {
            let i = NSMenuItem(title: "Kvaliteta: \(q.rawValue)", action: #selector(qualityAction(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = q.rawValue
            i.state = (q == quality) ? .on : .off
            m.addItem(i)
        }
        m.addItem(.separator())

        let mir = NSMenuItem(title: "Zrcalna slika", action: #selector(mirrorAction), keyEquivalent: "")
        mir.target = self
        mir.state = mirrored ? .on : .off
        m.addItem(mir)
        m.addItem(.separator())

        m.addItem(withTitle: "Izlaz", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc func toggleAction() { toggleVisible() }
    @objc func shapeAction(_ s: NSMenuItem) {
        if let raw = s.representedObject as? String, let sh = PanelShape(rawValue: raw) { applyShape(sh) }
    }
    @objc func sizeAction(_ s: NSMenuItem) { setWidth(CGFloat(s.tag)) }
    @objc func qualityAction(_ s: NSMenuItem) {
        if let raw = s.representedObject as? String, let q = Quality(rawValue: raw) { applyQuality(q) }
    }
    @objc func mirrorAction() { mirrored.toggle(); applyMirror(); UserDefaults.standard.set(mirrored, forKey: "mirrored") }
}


let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   
app.run()
