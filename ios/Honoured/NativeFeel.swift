import UIKit
import WebKit

/// Turns off the WebKit behaviour that gives the hosted web app away as a web
/// page: zooming in when a field takes focus (and on pinch or double tap),
/// selecting text and opening link callouts on a long press outside editable
/// fields, and the form bar above the keyboard.
enum NativeFeel {
    /// Call before the first load so the page script is in place for it.
    static func apply(to webView: WKWebView) {
        webView.configuration.userContentController.addUserScript(
            WKUserScript(source: pageScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        // A long press on a link would otherwise open a Safari-style preview.
        webView.allowsLinkPreview = false
        hideFormAccessoryBar(in: webView)
    }

    /// WebKit zooms into any field whose text is under 16 px when it takes
    /// focus and never zooms back out. Capping the viewport at 1x stops that,
    /// as well as pinch and double-tap zoom, without the web app having to
    /// enlarge its fields. The web app can re-render its head on navigation and
    /// put its own viewport back, so the rules are applied again whenever the
    /// head changes. Editable fields keep text selection so copy and paste
    /// still work in them.
    private static let pageScript = #"""
    (() => {
      const head = document.head;
      if (!head) return;

      const style = document.createElement('style');
      style.textContent = `
        html { -webkit-touch-callout: none; -webkit-user-select: none; user-select: none; }
        input, textarea, [contenteditable]:not([contenteditable="false"]) {
          -webkit-touch-callout: default; -webkit-user-select: text; user-select: text;
        }
      `;

      const lockScale = (content) => content
        .split(',')
        .map((part) => part.trim())
        .filter((part) => part && !/^(maximum-scale|user-scalable)\b/i.test(part))
        .concat('maximum-scale=1', 'user-scalable=no')
        .join(', ');

      const apply = () => {
        for (const meta of document.querySelectorAll('meta[name="viewport"]')) {
          const content = meta.getAttribute('content') || '';
          const locked = lockScale(content);
          if (content !== locked) meta.setAttribute('content', locked);
        }
        if (!style.isConnected) head.appendChild(style);
      };

      apply();
      new MutationObserver(apply).observe(head, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ['content'],
      });
    })();
    """#

    /// The bar with previous/next arrows and a Done button that WebKit shows
    /// above the keyboard is the `inputAccessoryView` of its private content
    /// view, so that one view is moved to a subclass returning nil there. The
    /// view is found by class name and left alone if a future WebKit renames
    /// it. The keyboard still closes with a tap outside the field.
    private static func hideFormAccessoryBar(in webView: WKWebView) {
        let selector = #selector(getter: UIResponder.inputAccessoryView)
        guard let contentView = webView.scrollView.subviews.first(where: {
                  object_getClass($0).map(NSStringFromClass) == "WKContentView"
              }),
              let contentClass = object_getClass(contentView),
              let original = class_getInstanceMethod(contentClass, selector) else { return }

        let subclassName = "HonouredWebContentView"
        var subclass: AnyClass? = NSClassFromString(subclassName)
        if subclass == nil, let created = objc_allocateClassPair(contentClass, subclassName, 0) {
            let noAccessoryView: @convention(block) (AnyObject) -> UIView? = { _ in nil }
            class_addMethod(created, selector, imp_implementationWithBlock(noAccessoryView), method_getTypeEncoding(original))
            objc_registerClassPair(created)
            subclass = created
        }
        if let subclass {
            object_setClass(contentView, subclass)
        }
    }
}
