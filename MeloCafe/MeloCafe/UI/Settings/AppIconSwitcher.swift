//
//  AppIconSwitcher.swift
//  MeloCafe
//
//  Created by Stossy11 on 18/6/2026.
//

import SwiftUI

struct AppIconSwitcher: View {
    @State var icons: [AppIconPosition] = [
        .init(creator: "Transistor", icons: [.init(id: "AppIcon", name: "App Icon", def: true), .init(id: "AppIcon-Classic", name: "Classic App Icon")]),
        .init(creator: "sky (@dootskyre)", icons: [
            .init(id: "PixelCafeAppIcon", name: "PixelCafé")
        ])
    ]

    var body: some View {
        List {
            ForEach(icons) { iconSet in
                Section(iconSet.creator) {
                    ForEach(iconSet.icons) { icon in
                        Button {
                            UIApplication.shared.setAlternateIconName(icon.id == "AppIcon" ? nil : icon.id)
                        } label: {
                            HStack {
                                AppIconView(app: icon.id)
                                    .frame(width: 60, height: 60)
                                    .aspectRatio(1, contentMode: .fill)
                                    .padding(.leading)
                                    .padding(.trailing, 8)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(icon.name)
                                        .font(.headline)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("App Icon Switcher")
    }
}

struct AppIconView: View {
    let app: String

    var body: some View {
        if let iconImage = UIImage(named: app) ?? UIImage.loadFromAssetsCatalog(named: app) {
            Image(uiImage: iconImage)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 15.0, style: .continuous))
                .clipped()
        } else {
            ZStack {
                Rectangle()
                    .foregroundStyle(.tertiary)

                ProgressView()
            }
            .clipShape(RoundedRectangle(cornerRadius: 15.0, style: .continuous))
        }
    }
}


extension UIImage {
    static func loadFromAssetsCatalog(named name: String) -> UIImage? {
        guard let carURL = Bundle.main.url(forResource: "Assets", withExtension: "car") else {
            print("Could not find Assets.car")
            return nil
        }
        
        guard let coreUIBundle = Bundle(path: "/System/Library/PrivateFrameworks/CoreUI.framework") else {
            print("Could not load CoreUI framework")
            return nil
        }
        
        if !coreUIBundle.isLoaded { coreUIBundle.load() }
        
        guard let catalogClass = NSClassFromString("CUICatalog") as? NSObject.Type else {
            print("Could not find CUICatalog class")
            return nil
        }
        
        let catalog = catalogClass.init()
        let initSel = NSSelectorFromString("initWithURL:error:")
        guard catalog.responds(to: initSel) else { return nil }
        
        var error: NSError?
        guard let validCatalog = withUnsafeMutablePointer(to: &error, { errorPtr in
            catalog.perform(initSel, with: carURL, with: errorPtr)?.takeUnretainedValue() as? NSObject
        }) else {
            print("Failed to init CUICatalog: \(error?.localizedDescription ?? "unknown")")
            return nil
        }
        
        let imagesWithNameSel = NSSelectorFromString("imagesWithName:")
        guard validCatalog.responds(to: imagesWithNameSel),
              let results = validCatalog.perform(imagesWithNameSel, with: name)?.takeUnretainedValue() as? [NSObject] else {
            print("imagesWithName: failed for: \(name)")
            return nil
        }
        
        let cuiNamedImageClass: AnyClass? = NSClassFromString("CUINamedImage")
        let cuiMultisizeClass: AnyClass? = NSClassFromString("CUINamedMultisizeImageSet")
        
        guard let namedImage = results.first(where: { obj in
            guard let cls = cuiNamedImageClass else { return false }
            if let multiCls = cuiMultisizeClass, obj.isKind(of: multiCls) { return false }
            return obj.isKind(of: cls) && obj.responds(to: NSSelectorFromString("image"))
        }) else {
            print("No CUINamedImage in results for: \(name)")
            return nil
        }
        
        let imageSel = NSSelectorFromString("image")
        guard namedImage.responds(to: imageSel) else { return nil }
        
        typealias ImageIMP = @convention(c) (NSObject, Selector) -> CGImage?
        let imageIMP = unsafeBitCast(namedImage.method(for: imageSel), to: ImageIMP.self)
        
        guard let cgImage = imageIMP(namedImage, imageSel) else {
            print("CGImageRef was nil for: \(name)")
            return nil
        }
        
        let scaleSel = NSSelectorFromString("scale")
        typealias ScaleIMP = @convention(c) (NSObject, Selector) -> Double
        let scaleIMP = unsafeBitCast(namedImage.method(for: scaleSel), to: ScaleIMP.self)
        let imageScale = CGFloat(scaleIMP(namedImage, scaleSel))
        
        return UIImage(cgImage: cgImage, scale: imageScale, orientation: .up)
    }
}
