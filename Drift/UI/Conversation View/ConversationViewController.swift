//
//  ConversationViewController.swift
//  Drift
//
//  Created by Brian McDonald on 28/07/2016.
//  Copyright © 2016 Drift. All rights reserved.
//

import UIKit
import QuickLook
import ObjectMapper
import SVProgressHUD


protocol AttachementSelectedDelegate: class{
    func attachmentSelected(_ attachment: Attachment, sender: AnyObject)
}

class ConversationViewController: UIViewController {
    
    enum ConversationType {
        case createConversation
        case continueConversation(conversationId: Int)
    }
    
    lazy var emptyState = ConversationEmptyStateView.fromNib() as! ConversationEmptyStateView
    var messages: [Message] = []
    var attachments: [Int: Attachment] = [:]
    var attachmentIds: Set<Int> = []
    var previewItem: DriftPreviewItem?
    var dateFormatter: DriftDateFormatter = DriftDateFormatter()
    var connectionBarView: ConnectionBarView = ConnectionBarView.fromNib() as! ConnectionBarView
    var connectionBarHeightConstraint: NSLayoutConstraint!
    
    var keyboardFrame: CGRect = .zero
    
    lazy var qlController = QLPreviewController()
    lazy var imagePicker = UIImagePickerController()
    lazy var interactionController = UIDocumentInteractionController()
    
    var welcomeUser: User?
    
    var conversationInputView: ConversationInputAccessoryView = ConversationInputAccessoryView()
    
    var tableView: UITableView!
    var ignoreKeyboardChanges = false
    var dimmingView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor(white: 0, alpha: 0.5)
        view.alpha = 0
        return view
    }()
    
    private var isFirstLayout: Bool = true

    override var inputAccessoryView: UIView? {
        return conversationInputView
    }
    
    override var canBecomeFirstResponder: Bool {
        return true
    }
    
    var conversationType: ConversationType! {
        didSet{
            if case ConversationType.continueConversation(let conversationId) = conversationType!{
                self.conversationId = conversationId
                InboxManager.sharedInstance.addMessageSubscription(MessageSubscription(delegate: self, conversationId: conversationId))
            }
        }
    }

    var conversationId: Int?{
        didSet{
            conversationInputView.addButton.isEnabled = true
            conversationInputView.textView.placeholder = "Message"
        }
    }
    
    var keyboardOffsetFrame: CGRect {
        guard let inputFrame = inputAccessoryView?.frame else { return .zero }
        return CGRect(origin: inputFrame.origin, size: CGSize(width: inputFrame.width, height: inputFrame.height))
    }
 
    class func navigationController(_ conversationType: ConversationType) -> UINavigationController {
        let vc = ConversationViewController(conversationType: conversationType)
        let navVC = UINavigationController(rootViewController: vc)
        
        let leftButton = UIBarButtonItem(image: UIImage(named: "closeIcon", in: Bundle(for: Drift.self), compatibleWith: nil), style: UIBarButtonItemStyle.plain, target:vc, action: #selector(ConversationViewController.dismissVC))
        leftButton.tintColor = DriftDataStore.sharedInstance.generateForegroundColor()
        vc.navigationItem.leftBarButtonItem  = leftButton

        return navVC
    }
    
    convenience init(conversationType: ConversationType) {
        self.init()
        self.conversationType = conversationType
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView = UITableView(frame: view.frame, style: .grouped)
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        view.addSubview(dimmingView)
        NSLayoutConstraint.activate([
            dimmingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimmingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimmingView.topAnchor.constraint(equalTo: view.topAnchor),
            dimmingView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])

        
        tableView.backgroundColor = UIColor.white
        tableView.separatorStyle = .none
        
        conversationInputView.addButton.isEnabled = false
        conversationInputView.textView.font = UIFont(name: "Avenir-Book", size: 15)
        if let organizationName = DriftDataStore.sharedInstance.embed?.organizationName {
            conversationInputView.textView.placeholder = "Message \(organizationName)"
        }else{
            conversationInputView.textView.placeholder = "Message"
        }
        
        tableView.register(UINib(nibName: "ConversationMessageTableViewCell", bundle: Bundle(for: ConversationMessageTableViewCell.classForCoder())), forCellReuseIdentifier: "ConversationMessageTableViewCell")
        
        if let navVC = navigationController {
            navVC.navigationBar.barTintColor = DriftDataStore.sharedInstance.generateBackgroundColor()
            navVC.navigationBar.tintColor = DriftDataStore.sharedInstance.generateForegroundColor()
            navVC.navigationBar.titleTextAttributes = [NSAttributedStringKey.foregroundColor: DriftDataStore.sharedInstance.generateForegroundColor(), NSAttributedStringKey.font: UIFont(name: "AvenirNext-Medium", size: 16)!]
            navigationItem.title = "Conversation"
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(ConversationViewController.didOpen), name: NSNotification.Name.UIApplicationWillEnterForeground, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(ConversationViewController.rotated), name: NSNotification.Name.UIDeviceOrientationDidChange, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(ConversationViewController.didReceiveNewMessage), name: .driftOnNewMessageReceived, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(ConversationViewController.connectionStatusDidUpdate), name: .driftSocketStatusUpdated, object: nil)

        tableView.dataSource = self
        tableView.delegate = self
        conversationInputView.delegate = self
        automaticallyAdjustsScrollViewInsets = false
        if #available(iOS 11.0, *) {
            tableView.contentInsetAdjustmentBehavior = .never
        }
        
        tableView.tableFooterView = UIView()
        tableView.transform = CGAffineTransform(rotationAngle: CGFloat.pi)
        tableView.keyboardDismissMode = .interactive
        
        tableView.scrollIndicatorInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: view.frame.width - 10)
        
        tableView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard)))
        
        tableView.becomeFirstResponder()
        
        connectionBarView.translatesAutoresizingMaskIntoConstraints = false

        connectionBarHeightConstraint = connectionBarView.heightAnchor.constraint(equalToConstant: 4)
        
        view.addSubview(connectionBarView)

        NSLayoutConstraint.activate([
            connectionBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            connectionBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            connectionBarView.topAnchor.constraint(equalTo: topLayoutGuide.bottomAnchor),
            connectionBarHeightConstraint
        ])
        didOpen()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        markConversationRead()
    }
    
    open override func viewDidLayoutSubviews() {
        // Hack to prevent animation of the contentInset after viewDidAppear
        if isFirstLayout {
            defer { isFirstLayout = false }
            NotificationCenter.default.addObserver(self, selector: #selector(keyboardFrameWillChange(notification:)), name: Notification.Name.UIKeyboardWillChangeFrame, object: nil)
            tableView.contentInset.top = keyboardOffsetFrame.height
            tableView.contentInset.bottom = topLayoutGuide.length
            tableView.scrollIndicatorInsets.top = keyboardOffsetFrame.height
            tableView.scrollIndicatorInsets.bottom = topLayoutGuide.length + connectionBarView.frame.height
            let offset = CGPoint(x: 0, y: -self.tableView.contentInset.top)
            tableView.setContentOffset(offset, animated: false)
        }
    }
    
    @objc func keyboardFrameWillChange(notification: Notification) {
        let endFrame = notification.userInfo?[UIKeyboardFrameEndUserInfoKey] as? CGRect
        
        keyboardFrame = endFrame ?? .zero
        
        if ignoreKeyboardChanges {
            return
        }
        
        if let endFrame = endFrame {
            
            if (endFrame.origin.y + endFrame.size.height) > UIScreen.main.bounds.height {
                // Hardware keyboard is found
                self.tableView.contentInset.top = view.frame.size.height - endFrame.origin.y
            } else {
                //Software keyboard is found
                let afterBottomInset = endFrame.height > keyboardOffsetFrame.height ? endFrame.height : keyboardOffsetFrame.height
                let differenceOfBottomInset = afterBottomInset - tableView.contentInset.top
                let contentOffset = CGPoint(x: tableView.contentOffset.x, y: tableView.contentOffset.y - differenceOfBottomInset)
                
                self.tableView.contentOffset = contentOffset
                self.tableView.contentInset.top = afterBottomInset
                self.tableView.scrollIndicatorInsets.top = afterBottomInset
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc func connectionStatusDidUpdate(notification: Notification) {
        if let status = notification.userInfo?["connectionStatus"] as? ConnectionStatus {
            connectionBarView.didUpdateStatus(status: status)
            showConnectionBar()
        }
    }
    
    func showConnectionBar() {

        UIView.animate(withDuration: 0.3) {
            self.connectionBarView.connectionStatusLabel.isHidden = false
            self.connectionBarHeightConstraint.constant = 30
            self.view.setNeedsUpdateConstraints()
            self.view.layoutIfNeeded()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(2000)) {
            self.hideConnectionBar()
        }
    }
    
    func hideConnectionBar(){
        view.setNeedsUpdateConstraints()
        view.layoutIfNeeded()
        connectionBarHeightConstraint.constant = 4
        UIView.animate(withDuration: 0.3) {
            self.connectionBarView.connectionStatusLabel.isHidden = true
            self.view.layoutIfNeeded()
        }
    }

    
    @objc func didOpen() {
        switch conversationType! {
        case .continueConversation(let conversationId):
            self.conversationId = conversationId
            getMessages(conversationId)
        case .createConversation:

            
            if let embed = DriftDataStore.sharedInstance.embed {
      
                emptyState.messageLabel.text = embed.getWelcomeMessageForUser() ?? ""
                
                welcomeUser = embed.getUserForWelcomeMessage()
                if let welcomeUser = welcomeUser {
                    if welcomeUser.bot {
                        
                        emptyState.avatarImageView.image = UIImage(named: "robot", in: Bundle(for: Drift.self), compatibleWith: nil)
                        emptyState.avatarImageView.backgroundColor = DriftDataStore.sharedInstance.generateBackgroundColor()
                        
                    } else if let avatarURLString = welcomeUser.avatarURL, let avatarURL = URL(string: avatarURLString) {
                        emptyState.avatarImageView.af_setImage(withURL: avatarURL)
                    }
                } else {
                    emptyState.avatarImageView.image = nil
                    emptyState.avatarImageView.backgroundColor = .clear
                }
            }
            
            if emptyState.superview == nil {
            
                emptyState.translatesAutoresizingMaskIntoConstraints = false
                view.addSubview(emptyState)
                
                NSLayoutConstraint.activate([
                    emptyState.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                    emptyState.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                    emptyState.topAnchor.constraint(equalTo: topLayoutGuide.bottomAnchor)
                ])
                
                let label = UILabel(frame: CGRect(x: 0, y: 0, width: tableView.frame.width, height: 30))
                label.textAlignment = .center
                label.text = "We're ⚡️ by Drift"
                label.font = UIFont(name: "Avenir-Book", size: 14)
                label.textColor = ColorPalette.grayColor
                label.transform = tableView.transform
                tableView.tableHeaderView = label
            }
        }
    }
    
    @objc func rotated() {
        if UIDeviceOrientationIsLandscape(UIDevice.current.orientation) {
            if UIDevice.current.userInterfaceIdiom == .phone {
                emptyState.avatarImageView.isHidden = true
                if emptyState.isHidden == false && emptyState.alpha == 1.0 && max(UIScreen.main.bounds.size.width, UIScreen.main.bounds.size.height) <= 568.0{
                    emptyState.isHidden = true
                }
            }

        }
        
        if UIDeviceOrientationIsPortrait(UIDevice.current.orientation) {
            emptyState.avatarImageView.isHidden = false
            if emptyState.isHidden == true && emptyState.alpha == 1.0 && UIDevice.current.userInterfaceIdiom == .phone && max(UIScreen.main.bounds.size.width, UIScreen.main.bounds.size.height) <= 568.0{
                emptyState.isHidden = false
            }
        }
    }
    
    @objc func dismissVC() {
        dismissKeyboard()
        dismiss(animated: true, completion: nil)
    }
    
    @objc func didReceiveNewMessage(notification: Notification) {
        
        if let message = notification.userInfo?["message"] as? Message {
            if message.conversationId == conversationId {
                newMessage(message)
            }
        }
    }
    
    func addMessageToConversation(_ message: Message){
        if messages.count > 0, let _ = messages.index(where: { (currentMessage) -> Bool in
            if message.requestId == currentMessage.requestId{
                return true
            }
            return false
        }){
            //We've already added this message, it may have failed to send
        }else{
            messages.insert(message, at: 0)
            tableView!.insertRows(at: [IndexPath(row: 0, section: 0)], with: .bottom)
        }
    }
    
    func getMessages(_ conversationId: Int){
        SVProgressHUD.show()
        DriftAPIManager.getMessages(conversationId, authToken: DriftDataStore.sharedInstance.auth!.accessToken) { (result) in
            SVProgressHUD.dismiss()
            switch result{
            case .success(var messages):
                self.messages = messages.sortMessagesForConversation()
                self.markConversationRead()
                self.tableView?.reloadData()
            case .failure:
                LoggerManager.log("Unable to get messages for conversationId: \(conversationId)")
            }
        }
    }
    
    func markConversationRead() {
        if let lastMessageId = self.messages.first?.id {
            DriftAPIManager.markConversationAsRead(messageId: lastMessageId) { (result) in
                switch result {
                case .success(_):
                    LoggerManager.log("Successfully marked conversation as read")
                case .failure(let error):
                    LoggerManager.didRecieveError(error)
                }
            }
        }
    }
    
    func getContext() -> Context {
        let context = Context()
        context.userAgent = "Mobile App / \(UIDevice.current.modelName) / \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] {
            context.userAgent?.append(" / App Version: \(version)")
        }
        return context
    }
    
    func postMessage(_ messageRequest: Message){
        if messageRequest.requestId == 0{
            messageRequest.requestId = Date().timeIntervalSince1970
        }
        messageRequest.type = Type.Chat
        messageRequest.context = getContext()
        addMessageToConversation(messageRequest)
        
        switch conversationType! {
        case .createConversation:
            createConversationWithMessage(messageRequest)
        case .continueConversation(let conversationId):
            postMessageToConversation(conversationId, messageRequest: messageRequest)
        }
    }
    
    func postMessageToConversation(_ conversationId: Int, messageRequest: Message) {
        InboxManager.sharedInstance.postMessage(messageRequest, conversationId: conversationId) { (message, requestId) in
            if let index = self.messages.index(where: { (message) -> Bool in
                if message.requestId == messageRequest.requestId{
                    return true
                }
                return false
            }){
                if let message = message{
                    message.sendStatus = .Sent
                    self.messages[index] = message
                }else{
                    messageRequest.sendStatus = .Failed
                    self.messages[index] = messageRequest
                }
                
                self.tableView!.reloadRows(at: [IndexPath(row:index, section: 0)], with: .none)
                self.tableView?.scrollToRow(at: IndexPath(row:0, section: 0), at: .bottom, animated: true)
            }
        }
    }
    
    func createConversationWithMessage(_ messageRequest: Message) {
        InboxManager.sharedInstance.createConversation(messageRequest, welcomeMessageUser: welcomeUser, welcomeMessage: DriftDataStore.sharedInstance.embed?.getWelcomeMessageForUser()) { (message, requestId) in
            if let message = message{
                self.conversationType = ConversationType.continueConversation(conversationId: message.conversationId)
                message.sendStatus = .Sent
                self.messages[0] = message
                self.didOpen()
            }else{
                let message = Message()
                message.authorId = DriftDataStore.sharedInstance.auth?.enduser?.userId
                message.body = messageRequest.body
                message.requestId = messageRequest.requestId
                message.sendStatus = .Failed
                self.messages[0] = message
            }
            
            self.tableView!.reloadRows(at: [IndexPath(row:0, section: 0)], with: .none)
            self.tableView?.scrollToRow(at: IndexPath(row:0, section: 0), at: .bottom, animated: true)
        }
    }
    
}

extension ConversationViewController: ConversationInputAccessoryViewDelegate {
    
    
    func expandingKeyboard() {
        ignoreKeyboardChanges = true

        UIView.animate(withDuration: 0.3, animations: {
            self.dimmingView.alpha = 1
        })
    }
    
    func compressingKeyboard() {
        UIView.animate(withDuration: 0.3, animations: {
            self.dimmingView.alpha = 0
        }) { (success) in
            if success {
                self.ignoreKeyboardChanges = false
            }
        }
    }
    
    func getKeyboardRect() -> CGRect {
        return keyboardFrame
    }
    
    func didPressLeftButton() {
        dismissKeyboard()
        let uploadController = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        
        if UIDevice.current.userInterfaceIdiom == UIUserInterfaceIdiom.pad {
            uploadController.modalPresentationStyle = .popover
            let popover = uploadController.popoverPresentationController
            popover?.sourceView = self.conversationInputView.addButton
            popover?.sourceRect = self.conversationInputView.addButton.bounds
        }
        
        imagePicker.delegate = self
        
        uploadController.addAction(UIAlertAction(title: "Take a Photo", style: .default, handler: { (UIAlertAction) in
            self.imagePicker.sourceType = .camera
            self.present(self.imagePicker, animated: true, completion: nil)
        }))
        
        uploadController.addAction(UIAlertAction(title: "Choose From Library", style: .default, handler: { (UIAlertAction) in
            self.imagePicker.sourceType = .photoLibrary
            self.present(self.imagePicker, animated: true, completion: nil)
        }))
        
        uploadController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(uploadController, animated: true, completion: nil)
    }
    
    func didPressRightButton() {
        let message = Message()
        message.body = conversationInputView.textView.text
        message.authorId = Int(DriftDataStore.sharedInstance.auth!.enduser!.externalId!)
        message.sendStatus = .Pending
        conversationInputView.textView.text  = ""
        postMessage(message)
    }
    
    @objc func dismissKeyboard(){
        conversationInputView.textView.resignFirstResponder()
    }
    
}

extension ConversationViewController : UITableViewDelegate, UITableViewDataSource{

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let message = messages[indexPath.row]
        
        var showHeader = true
        if (indexPath.row + 1) < messages.count {
            let pastMessage = messages[indexPath.row + 1]
            showHeader = !Calendar.current.isDate(pastMessage.createdAt, inSameDayAs: message.createdAt)
        }
        
        var cell: UITableViewCell
        cell = tableView.dequeueReusableCell(withIdentifier: "ConversationMessageTableViewCell", for: indexPath) as!ConversationMessageTableViewCell
        if let cell = cell as? ConversationMessageTableViewCell{
            cell.delegate = self
            cell.indexPath = indexPath
            cell.setupForMessage(message: message, showHeader: showHeader, configuration: DriftDataStore.sharedInstance.embed)
        }
        
        cell.transform = tableView.transform
        cell.setNeedsLayout()
        return cell
        
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        if messages.count > 0 && !emptyState.isHidden{
            UIView.animate(withDuration: 0.4, animations: {
                self.emptyState.alpha = 0.0
            }, completion: { (_) in
                self.emptyState.isHidden = true
            })
        }
        return messages.count
    }
    
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        
        let message = messages[indexPath.row]
        if message.sendStatus == .Failed{
            let alert = UIAlertController(title:nil, message: nil, preferredStyle: .actionSheet)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
            alert.addAction(UIAlertAction(title:"Retry Send", style: .default, handler: { (_) -> Void in
                message.sendStatus = .Pending
                self.messages[indexPath.row] = message
                self.tableView!.reloadRows(at: [indexPath], with: .none)
                self.postMessage(message)
            }))
            alert.addAction(UIAlertAction(title:"Delete Message", style: .destructive, handler: { (_) -> Void in
                self.messages.remove(at: self.messages.count-indexPath.row-1)
                self.tableView!.deleteRows(at: [indexPath as IndexPath], with: .none)
            }))
            
            present(alert, animated: true, completion: nil)
        }
    }
    
    
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        let message = messages[indexPath.row]
        
        if message.attachments.count > 0 {
            return 300
        }else{
            return 150
        }
    }
}

extension ConversationViewController: MessageDelegate {
    
    func messagesDidUpdate(_ messages: [Message]) {
        let sorted = messages.sorted(by: { $0.createdAt.compare($1.createdAt as Date) == .orderedDescending})
        self.messages = sorted
        self.tableView?.reloadData()
    }
    
    func newMessage(_ message: Message) {
        if let id = message.id{
            ConversationsManager.markMessageAsRead(id)
        }
        if message.authorId != DriftDataStore.sharedInstance.auth?.enduser?.userId{
            if let index = messages.index(of: message){
                messages[index] = message
            
                tableView!.reloadRows(at: [IndexPath(row: index, section: 0)], with: .bottom)
            }else{
                messages.insert(message, at: 0)
                tableView!.insertRows(at: [IndexPath(row: 0, section: 0)], with: .bottom)
            }
        }
    }
}

extension ConversationViewController: AttachementSelectedDelegate {
    
    func attachmentSelected(_ attachment: Attachment, sender: AnyObject) {
        SVProgressHUD.show()
        DriftAPIManager.downloadAttachmentFile(attachment, authToken: (DriftDataStore.sharedInstance.auth?.accessToken)!) { (result) in
            DispatchQueue.main.async {
                SVProgressHUD.dismiss()
            }
            switch result{
            case .success(let tempFileURL):
                if attachment.isImage(){
                    DispatchQueue.main.async {
                        self.previewItem = DriftPreviewItem(url: tempFileURL, title: attachment.fileName)
                        self.qlController.dataSource = self
                        self.qlController.reloadData()
                        self.present(self.qlController, animated: true, completion:nil)
                    }
                }else{
                    DispatchQueue.main.async {
                        self.interactionController.url = tempFileURL
                        self.interactionController.name = attachment.fileName
                        self.interactionController.presentOptionsMenu(from: CGRect.zero, in: self.view, animated: true)
                    }
                }
            case .failure:
                let alert = UIAlertController(title: "Unable to preview file", message: "This file cannot be previewed", preferredStyle: UIAlertControllerStyle.alert)
                alert.addAction(UIAlertAction(title: "OK", style: UIAlertActionStyle.default, handler: nil))
                self.present(alert, animated: true, completion: nil)
                LoggerManager.log("Unable to preview file with mimeType: \(attachment.mimeType)")
            }
        }
    }
}

extension ConversationViewController: QLPreviewControllerDataSource {
    
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return 1
    }
    
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        if let previewItem = previewItem{
            return previewItem
        }
        return DriftPreviewItem(url: URLComponents().url!, title: "")
    }
}

extension ConversationViewController: UIDocumentInteractionControllerDelegate{
    
    func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController {
        return self
    }
    
    func documentInteractionControllerViewForPreview(_ controller: UIDocumentInteractionController) -> UIView? {
        return self.view
    }
    
    func documentInteractionControllerRectForPreview(_ controller: UIDocumentInteractionController) -> CGRect {
        return self.view.frame
    }
}

extension ConversationViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion: nil)
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        picker.dismiss(animated: true, completion: nil)

        if let image = info[UIImagePickerControllerOriginalImage] as? UIImage {
            if let imageRep = UIImageJPEGRepresentation(image, 0.2){
                let newAttachment = Attachment()
                newAttachment.data = imageRep
                newAttachment.conversationId = conversationId!
                newAttachment.mimeType = "image/jpeg"
                newAttachment.fileName = "image.jpg"
                
                DriftAPIManager.postAttachment(newAttachment,authToken: DriftDataStore.sharedInstance.auth!.accessToken) { (result) in
                    switch result{
                    case .success(let attachment):
                        let messageRequest = Message()
                        messageRequest.attachmentIds.append(attachment.id)
                        self.postMessage(messageRequest)
                    case .failure:
                        let alert = UIAlertController(title: "Unable to upload file", message: nil, preferredStyle: UIAlertControllerStyle.alert)
                        alert.addAction(UIAlertAction(title: "OK", style: UIAlertActionStyle.default, handler: nil))
                        self.present(alert, animated: true, completion: nil)
                        LoggerManager.log("Unable to upload file with mimeType: \(newAttachment.mimeType)")
                        
                    }
                }
            }
        }
    }    
}
