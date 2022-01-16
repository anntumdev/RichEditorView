//
//  RichEditor.swift
//
//  Created by Caesar Wirth on 4/1/15.
//  Updated/Modernized by C. Bess on 9/18/19.
//
//  Copyright (c) 2015 Caesar Wirth. All rights reserved.
//

import UIKit
import WebKit
        
/// RichEditorDelegate defines callbacks for the delegate of the RichEditorView
@objc public protocol RichEditorDelegate: AnyObject {
    /// Called when the inner height of the text being displayed changes
    /// Can be used to update the UI
    @objc optional func richEditor(_ editor: RichEditorView, heightDidChange height: Int)
    
    /// Called whenever the content inside the view changes
    @objc optional func richEditor(_ editor: RichEditorView, contentDidChange content: String)
    
    /// Called when the rich editor starts editing
    @objc optional func richEditorTookFocus(_ editor: RichEditorView)
    
    /// Called when the rich editor stops editing or loses focus
    @objc optional func richEditorLostFocus(_ editor: RichEditorView)
    
    /// Called when the RichEditorView has become ready to receive input
    /// More concretely, is called when the internal WKWebView loads for the first time, and contentHTML is set
    @objc optional func richEditorDidLoad(_ editor: RichEditorView)
    
    /// Called when the internal WKWebView begins loading a URL that it does not know how to respond to
    /// For example, if there is an external link, and then the user taps it
    @objc optional func richEditor(_ editor: RichEditorView, shouldInteractWith url: URL) -> Bool
    
    /// Called when custom actions are called by callbacks in the JS
    /// By default, this method is not used unless called by some custom JS that you add
    @objc optional func richEditor(_ editor: RichEditorView, handle action: String)
    
    /// Called when the selection range changes (or caret position changes)
    /// The `attrs` provide the active attributes for the selection (e.g. bold, italic, etc)
    @objc optional func richEditor(_ editor: RichEditorView, selectionDidChange selection: [Int], attributes attrs: [String])
}

/// RichEditorView is a UIView that displays richly styled text, and allows it to be edited in a WYSIWYG fashion.
@objcMembers open class RichEditorView: UIView, UIScrollViewDelegate, WKNavigationDelegate, UIGestureRecognizerDelegate {
    /// The delegate that will receive callbacks when certain actions are completed.
    open weak var delegate: RichEditorDelegate?
    
    /// Input accessory view to display over they keyboard.
    /// Defaults to nil
    open override var inputAccessoryView: UIView? {
        get { return webView.accessoryView }
        set { webView.accessoryView = newValue }
    }
    
    /// The internal WKWebView that is used to display the editor.
    open private(set) var webView: RichEditorWebView
    
    /// Whether or not scroll is enabled on the view.
    open var isScrollEnabled: Bool = true {
        didSet {
            webView.scrollView.isScrollEnabled = isScrollEnabled
        }
    }
    
    /// Whether or not to allow user input in the view.
    open var editingEnabled: Bool = false {
        didSet { contentEditable = editingEnabled }
    }
    
    /// The content HTML of the text being displayed.
    /// Is continually updated as the text is being edited.
    open private(set) var contentHTML: String = "" {
        didSet {
            if isReady {
                delegate?.richEditor?(self, contentDidChange: contentHTML)
            }
        }
    }
    
    /// The internal height of the text being displayed.
    /// Is continually being updated as the text is edited.
    open private(set) var editorHeight: Int = 0 {
        didSet {
            delegate?.richEditor?(self, heightDidChange: editorHeight)
        }
    }
        
    /// Whether or not the editor DOM element has finished loading or not yet.
    private var isEditorLoaded = false
    
    /// Indicates if the editor should begin sending events to the delegate
    private var isReady = false
    
    /// Value that stores whether or not the content should be editable when the editor is loaded.
    /// Is basically `isEditingEnabled` before the editor is loaded.
    private var editingEnabledVar = true
        
    /// The HTML that is currently loaded in the editor view, if it is loaded. If it has not been loaded yet, it is the
    /// HTML that will be loaded into the editor view once it finishes initializing.
    public var html: String = "" {
        didSet {
            setHTML(html)
        }
    }
    
    /// Private variable that holds the placeholder text, so you can set the placeholder before the editor loads.
    private var placeholderText: String = ""
    /// The placeholder text that should be shown when there is no user input.
    open var placeholder: String {
        get { return placeholderText }
        set {
            placeholderText = newValue
            if isEditorLoaded {
                runJS("RE.setPlaceholderText('\(newValue.escaped)')")
            }
        }
    }
        
    // MARK: Initialization
    
    public override init(frame: CGRect) {
        webView = RichEditorWebView()
        super.init(frame: frame)
        setup()
    }
    
    required public init?(coder aDecoder: NSCoder) {
        webView = RichEditorWebView()
        super.init(coder: aDecoder)
        setup()
    }
    
    private func setup() {
        // configure webview
        webView.frame = bounds
        webView.navigationDelegate = self
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.configuration.dataDetectorTypes = WKDataDetectorTypes()
        webView.scrollView.isScrollEnabled = isScrollEnabled
        webView.scrollView.bounces = true
        webView.scrollView.delegate = self
        webView.scrollView.clipsToBounds = false
        addSubview(webView)
        
        reloadHTML(with: html)
    }
    
    /// Reloads the HTML for the editor.
    /// - parameter html: The HTML that will be loaded into the editor view once it finishes initializing.
    /// - parameter headerHTML: The header HTML that will be inserted after the default styles.
    /// - parameter footerHTML: The footer HTML that will be inserted after the default JavaScript.
    public func reloadHTML(with html: String, headerHTML: String = "", footerHTML: String = "") {
        guard let filePath = Bundle(for: RichEditorView.self).path(forResource: "rich_editor", ofType: "html") else {
            return
        }
        
        let readerHtmlTemplate = try! String(contentsOfFile: filePath)
        let fullHtml = readerHtmlTemplate
            .replacingOccurrences(of: "{{header}}", with: headerHTML)
            .replacingOccurrences(of: "{{footer}}", with: footerHTML)
        
        webView.loadHTMLString(fullHtml, baseURL: URL(fileURLWithPath: filePath, isDirectory: false).deletingLastPathComponent())
        
        isEditorLoaded = false
        self.html = html
    }
    
    // MARK: - Rich Text Editing
    
    open func isEditingEnabled(handler: @escaping (Bool) -> Void) {
        isContentEditable(handler: handler)
    }
    
    private func setHTML(_ value: String) {
        if isEditorLoaded {
            runJS("RE.setHtml('\(value.escaped)')")
        }
    }
    
    /// The inner height of the editor div.
    /// Fetches it from JS every time, so might be slow!
    private func getClientHeight(handler: @escaping (Int) -> Void) {
        handler(0)
    }
    
    public func getHtml(handler: @escaping (String) -> Void) {
        runJS("RE.getHtml()") { r in
            handler(r as! String)
        }
    }
    
    /// Text representation of the data that has been input into the editor view, if it has been loaded.
    public func getText(handler: @escaping (String) -> Void) {
        runJS("RE.getText()") { r in
            handler(r as! String)
        }
    }
    
    /// The href of the current selection, if the current selection's parent is an anchor tag.
    /// Will be nil if there is no href, or it is an empty string.
    public func getSelectedHref(handler: @escaping (String?) -> Void) {
        hasRangeSelection(handler: { r in
            if !r {
                handler(nil)
                return
            }
            
            self.runJS("RE.getSelectedHref()") { r in
                let r = r as! String
                if r == "" {
                    handler(nil)
                } else {
                    handler(r)
                }
            }
        })
    }
    
    /// Whether or not the selection has a type specifically of "Range".
    public func hasRangeSelection(handler: @escaping (Bool) -> Void) {
        runJS("RE.rangeSelectionExists()") { val in
            handler((val as! NSString).boolValue)
        }
    }
    
    /// Whether or not the selection has a type specifically of "Range" or "Caret".
    public func hasRangeOrCaretSelection(handler: @escaping (Bool) -> Void) {
        runJS("RE.rangeOrCaretSelectionExists()") { val in
            handler((val as! NSString).boolValue)
        }
    }
    
    // MARK: Methods
    
    public func removeFormat() {
        runJS("RE.removeFormat()")
    }
    
    public func setFontSize(_ size: Int) {
        runJS("RE.setFontSize('\(size)px')")
    }
    
    public func setEditorBackgroundColor(_ color: UIColor) {
        runJS("RE.setBackgroundColor('\(color.hex)')")
    }
    
    public func undo() {
        runJS("RE.undo()")
    }
    
    public func redo() {
        runJS("RE.redo()")
    }
    
    public func bold() {
        runJS("RE.setBold()")
    }
    
    public func italic() {
        runJS("RE.setItalic()")
    }
    
    // "superscript" is a keyword
    public func subscriptText() {
        runJS("RE.setSubscript()")
    }
    
    public func superscript() {
        runJS("RE.setSuperscript()")
    }
    
    public func strikethrough() {
        runJS("RE.setStrikeThrough()")
    }
    
    public func underline() {
        runJS("RE.setUnderline()")
    }
    
    private func getColorHex(with color: UIColor?) -> String {
        // if no color, then clear the color style css
        return color?.hex == nil ? "null" : "'\(color!.hex)'"
    }
    
    public func setTextColor(_ color: UIColor?) {
        runJS("RE.prepareInsert()")
        let color = getColorHex(with: color)
        runJS("RE.setTextColor(\(color))")
    }
    
    public func setEditorFontColor(_ color: UIColor) {
        runJS("RE.setBaseTextColor('\(color.hex)')")
    }
    
    public func setTextBackgroundColor(_ color: UIColor?) {
        runJS("RE.prepareInsert()")
        let color = getColorHex(with: color)
        runJS("RE.setTextBackgroundColor(\(color))")
    }
    
    public func header(_ h: Int) {
        runJS("RE.setHeading('\(h)')")
    }
    
    public func indent() {
        runJS("RE.setIndent()")
    }
    
    public func outdent() {
        runJS("RE.setOutdent()")
    }
    
    public func orderedList() {
        runJS("RE.setOrderedList()")
    }
    
    public func unorderedList() {
        runJS("RE.setUnorderedList()")
    }
    
    public func blockquote() {
        runJS("RE.setBlockquote()");
    }
    
    public func alignLeft() {
        runJS("RE.setJustifyLeft()")
    }
    
    public func alignCenter() {
        runJS("RE.setJustifyCenter()")
    }
    
    public func alignRight() {
        runJS("RE.setJustifyRight()")
    }
    
    public func insertImage(_ url: String, alt: String) {
        runJS("RE.prepareInsert()")
        runJS("RE.insertImage('\(url.escaped)', '\(alt.escaped)')")
    }
    
    public func insertLink(_ href: String, title: String) {
        runJS("RE.prepareInsert()")
        runJS("RE.insertLink('\(href.escaped)', '\(title.escaped)')")
    }
    
    public func focus() {
        runJS("RE.focus()")
    }
    
    public func focus(at: CGPoint) {
        runJS("RE.focusAtPoint(\(at.x), \(at.y))")
    }
    
    public func blur() {
        runJS("RE.blurFocus()")
    }
    
    /// Runs some JavaScript on the WKWebView and returns the result
    /// If there is no result, returns an empty string
    /// - parameter js: The JavaScript string to be run
    /// - returns: The result of the JavaScript that was run
    public func runJS(_ js: String, handler: ((Any) -> Void)? = nil) {
        webView.evaluateJavaScript(js) { (result, error) in
            if let error = error {
                print("WKWebViewJavascriptBridge Error: \(String(describing: error)) - JS: \(js)")
                handler?("")
                return
            }
            
            guard let handler = handler else {
                return
            }
            
            guard let data = (result as? String)?.data(using: .utf8) else {
                handler(result ?? "")
                return
            }
            
            // handle result
            handler((try? JSONSerialization.jsonObject(with: data)) ?? result ?? "")
        }
    }
    
    // MARK: - Delegate Methods
    
    // MARK: UIScrollViewDelegate
    
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // We use this to keep the scroll view from changing its offset when the keyboard comes up
        if !isScrollEnabled {
            scrollView.bounds = webView.bounds
        }
    }
    
    // MARK: WKWebViewDelegate
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // empty
    }
    
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Handle pre-defined editor actions
        let callbackPrefix = "re-callback://"
        if navigationAction.request.url?.absoluteString.hasPrefix(callbackPrefix) == true {
            // When we get a callback, we need to fetch the command queue to run the commands
            // It comes in as a JSON array of commands that we need to parse
            runJS("RE.getCommandQueue()") { commands in
                if let jsonCommands = commands as? [String] {
                    jsonCommands.forEach(self.performCommand)
                } else {
                    print("RichEditorView: Failed to parse JSON Commands: \(commands)")
                }
            }
            return decisionHandler(WKNavigationActionPolicy.cancel);
        }
        
        // User is tapping on a link, so we should react accordingly
        if navigationAction.navigationType == .linkActivated {
            if let url = navigationAction.request.url {
                if delegate?.richEditor?(self, shouldInteractWith: url) ?? false {
                    return decisionHandler(WKNavigationActionPolicy.allow)
                } else {
                    return decisionHandler(WKNavigationActionPolicy.cancel)
                }
            }
        }
        
        return decisionHandler(WKNavigationActionPolicy.allow);
    }
    
    // MARK: UIGestureRecognizerDelegate
    
    /// Delegate method for our UITapGestureDelegate.
    /// Since the internal web view also has gesture recognizers, we have to make sure that we actually receive our taps.
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
    
    // MARK: - Private Implementation Details
    
    private var contentEditable: Bool = false {
        didSet {
            editingEnabledVar = contentEditable
            if isEditorLoaded {
                let value = (contentEditable ? "true" : "false")
                runJS("RE.setEditable(\(value))")
            }
        }
    }
    
    private func isContentEditable(handler: @escaping (Bool) -> Void) {
        if isEditorLoaded {
            runJS("RE.getEditable()") { value in
                self.editingEnabledVar = value as? Bool ?? false
            }
        } else {
            handler(false)
        }
    }
    
    /// The position of the caret relative to the currently shown content.
    /// For example, if the cursor is directly at the top of what is visible, it will return 0.
    /// This also means that it will be negative if it is above what is currently visible.
    /// Can also return 0 if some sort of error occurs between JS and here.
    private func relativeCaretYPosition(handler: @escaping (Int) -> Void) {
        runJS("RE.getRelativeCaretYPosition()") { r in
            handler(r as? Int ?? 0)
        }
    }
        
    /// Called when actions are received from JavaScript
    /// - parameter method: String with the name of the method and optional parameters that were passed in
    private func performCommand(_ method: String) {
        if method.hasPrefix("ready") {
            // If loading for the first time, we have to set the content HTML to be displayed
            if !isEditorLoaded {
                isEditorLoaded = true
                setHTML(html)
                contentHTML = html
                contentEditable = editingEnabledVar
                placeholder = placeholderText
                
                delegate?.richEditorDidLoad?(self)
                isReady = true
            }
        } else if method.hasPrefix("input") {
            runJS("RE.getHtml()") { content in
                self.contentHTML = content as! String
            }
        } else if method.hasPrefix("focus") {
            delegate?.richEditorTookFocus?(self)
        } else if method.hasPrefix("blur") {
            delegate?.richEditorLostFocus?(self)
        } else if method.hasPrefix("action/") {
            runJS("RE.getHtml()") { content in
                self.contentHTML = content as! String
                
                // If there are any custom actions being called
                // We need to tell the delegate about it
                let actionPrefix = "action/"
                let range = method.range(of: actionPrefix)!
                let action = method.replacingCharacters(in: range, with: "")
                
                self.delegate?.richEditor?(self, handle: action)
            }
        } else if method.hasPrefix("selection") {
            runJS("RE.getSelectedRange()") { range in
                self.runJS("RE.getActiveAttributes()") { attrs in
//                    print("range: \(range) - attrs: \(attrs)")
                    self.delegate?.richEditor?(self, selectionDidChange: range as! [Int], attributes: attrs as! [String])
                }
            }
        }
    }
    
    // MARK: - Responder Handling
    
    override open func becomeFirstResponder() -> Bool {
        if !webView.isFirstResponder {
            focus()
            return true
        } else {
            return false
        }
    }
    
    open override func resignFirstResponder() -> Bool {
        blur()
        return true
    }
    
}
