//
//  DriftAPIManager.swift
//  Drift
//
//  Copyright © 2016 Drift. All rights reserved.
//

import Foundation
import Alamofire

class DriftAPIManager: Alamofire.Session {
    
    static let sharedManager: DriftAPIManager = {
        let configuration = URLSessionConfiguration.af.default
        if let info = Bundle.main.infoDictionary {
            let driftVersion: String = {
                guard let afInfo = Bundle(for: Drift.self).infoDictionary, let build = afInfo["CFBundleShortVersionString"] as? String else { return "Unknown" }
                return build
            }()
            
            let identifer = info["CFBundleIdentifier"] as? String ?? "Unknown"
            let build = info["CFBundleVersion"] as? String ?? "Unknown"
            let osName = UIDevice.current.systemName
            let osVersion = UIDevice.current.systemVersion
            let alamofireVersion: String = {
                guard let afInfo = Bundle(for: Session.self).infoDictionary, let build = afInfo["CFBundleShortVersionString"] as? String else { return "Unknown" }
                return "Alamofire/\(build)"
            }()
            let userAgent = "Drift-SDK/\(driftVersion) (\(identifer); build:\(build); \(osName) \(osVersion)) \(alamofireVersion)"
            configuration.httpAdditionalHeaders?["User-Agent"] = userAgent
        }
        return DriftAPIManager(configuration: configuration)
    }()
    
    class func jsonDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
    
    class func getAuth(_ email: String?, userId: String, userJwt: String?, redirectURL: String, orgId: Int, clientId: String, completion: @escaping (Swift.Result<Auth, Error>) -> ()) {
        sharedManager.request(DriftCustomerRouter.getAuth(email: email,
                                                          userId: userId,
                                                          userJwt:userJwt,
                                                          redirectURL: redirectURL,
                                                          orgId: orgId,
                                                          clientId: clientId)).driftResponseDecodable(completionHandler: { (response: DataResponse<AuthDTO, AFError>) in
                                                            completion(mapResponse(response))
                                                          })
    }
    
    class func getSocketAuth(orgId: Int, accessToken: String, completion: @escaping (Swift.Result<SocketAuth, Error>) -> ()) {
        sharedManager.request(DriftRouter.getSocketData(orgId: orgId,
                                                        accessToken: accessToken)).driftResponseDecodable(completionHandler: { (response: DataResponse<SocketAuthDTO, AFError>) in
                                                            completion(mapResponse(response))
                                                        })
    }

    class func getEmbeds(_ embedId: String, refreshRate: Int?, completion: @escaping (Swift.Result<Embed, Error>) -> ()){
        sharedManager.request(DriftRouter.getEmbed(embedId: embedId,
                                                   refreshRate: refreshRate)).driftResponseDecodable(completionHandler: { (response: DataResponse<EmbedDTO, AFError>) in
                                                    completion(mapResponse(response))
                                                   })
    }
    
    class func getUser(_ userId: Int64, orgId: Int, authToken:String, completion: @escaping (Swift.Result<[User], Error>) -> ()) {
        sharedManager.request(DriftCustomerRouter.getUser(orgId: orgId, userId: userId)).driftResponseDecodable(completionHandler: { (response: DataResponse<[UserDTO], AFError>) in
            completion(mapResponseArr(response))
        })
    }
    
    class func getEndUser(_ endUserId: Int64, authToken:String, completion: @escaping (Swift.Result<User, Error>) -> ()){
        sharedManager.request(DriftCustomerRouter.getEndUser(endUserId: endUserId)).driftResponseDecodable(completionHandler: { (response: DataResponse<UserDTO, AFError>) in
            completion(mapResponse(response))
        })
    }
    
    class func getUserAvailability(_ userId: Int64, completion: @escaping (Swift.Result<UserAvailability, Error>) -> ()) {
        sharedManager.request(DriftCustomerRouter.getUserAvailability(userId: userId)).driftResponseDecodable(completionHandler: { (response: DataResponse<UserAvailabilityDTO, AFError>) in
            completion(mapResponse(response))
        })
    }
    
    class func scheduleMeeting(_ userId: Int64, conversationId: Int64, timestamp: Double, completion: @escaping (Swift.Result<GoogleMeeting, Error>) -> ()) {
        sharedManager.request(DriftCustomerRouter.scheduleMeeting(userId: userId, conversationId: conversationId, timestamp: timestamp)).driftResponseDecodable(completionHandler: { (response: DataResponse<GoogleMeetingDTO, AFError>) in
          
            if response.response?.statusCode == 200 {
                LoggerManager.log("Scheduled Meeting Success: \(String(describing: response.value))")
                completion(mapResponse(response))
            } else {
                LoggerManager.log("Scheduled Meeting Failure: \(String(describing: response.response?.statusCode))")
                completion(.failure(DriftError.apiFailure))
            }
        })
    }
    
    
    class func postIdentify(_ orgId: Int, userId: String, email: String?, userJwt: String?, attributes: [String: Any]?, completion: @escaping (Swift.Result<User, Error>) -> ()) {
        var params: [String: Any] = [
            "orgId": orgId,
            "userId": userId,
            "attributes": ["email": email]
        ]
        
        if let userJwt = userJwt {
            params["signedIdentity"] = userJwt
        }
        
        if var attributes = attributes {
            attributes["email"] = email
            params["attributes"] = attributes
        }
        
        sharedManager.request(DriftRouter.postIdentify(params: params)).driftResponseDecodable(completionHandler: { (response: DataResponse<UserDTO, AFError>) in
            completion(mapResponse(response))
        })
    }
    
    class func markMessageAsRead(messageId: Int64, completion: @escaping (_ result: Result<Bool>) -> ()){
        sharedManager.request(DriftConversation2Router.markMessageAsRead(messageId: messageId)).responseString { (result) in
            switch result.result{
            case .success:
                completion(.success(true))
            case .failure(let error):
                completion(.failure(error))
            }
        }
        
    }
    
    class func markConversationAsRead(messageId: Int64, completion: @escaping (_ result: Result<Bool>) -> ()){
        sharedManager.request(DriftConversation2Router.markConversationAsRead(messageId: messageId)).responseString { (result) in
            switch result.result{
            case .success:
                completion(.success(true))
            case .failure(let error):
                completion(.failure(error))
            }
        }
        
    }
        
    class func getEnrichedConversations(_ endUserId: Int64, completion: @escaping (_ result: Swift.Result<[EnrichedConversation], Error>) -> ()){
        sharedManager.request(DriftConversationRouter.getEnrichedConversationsForEndUser(endUserId: endUserId)).driftResponseDecodable(completionHandler: { (response: DataResponse<[EnrichedConversationDTO], AFError>) in
            completion(mapResponseArr(response))
        })
    }
        
    class func getMessages(_ conversationId: Int64, authToken: String, completion: @escaping (_ result: Swift.Result<[Message], Error>) -> ()){
        sharedManager.request(DriftConversationRouter.getMessagesForConversation(conversationId: conversationId)).driftResponseDecodable(completionHandler: { (response: DataResponse<[MessageDTO], AFError>) in
            completion(mapResponseArr(response))
        })
    }
    
    class func postMessage(_ conversationId: Int64, messageRequest: MessageRequest, completion: @escaping (_ result: Swift.Result<Message, Error>) -> ()){
        let json = messageRequest.toJSON()
        
        sharedManager.request(DriftMessagingRouter.postMessageToConversation(conversationId: conversationId, message: json)).driftResponseDecodable(completionHandler: { (response: DataResponse<MessageDTO, AFError>) in
            completion(mapResponse(response))
        })
    }
    
    class func createConversation(_ body: String, welcomeUserId: Int64?, welcomeMessage: String?, authToken: String, completion: @escaping (_ result: Swift.Result<Message, Error>) -> ()){
        
        var data: [String: Any] = [:]
        
        data["body"] = body
        
        if let welcomeUserId = welcomeUserId, let welcomeMessage = welcomeMessage {
            
            let preMessage : [String: Any] = [
                "body": welcomeMessage,
                "sender": ["id":welcomeUserId]
            ]

            data["attributes"] = [
                "preMessages": [preMessage],
                "sentWelcomeMessage": true]
            
        }
        
        sharedManager.request(DriftMessagingRouter.createConversation(data: data)).driftResponseDecodable(completionHandler: { (response: DataResponse<MessageDTO, AFError>) in
            completion(mapResponse(response))
        })
    }
    
    class func downloadAttachmentFile(_ attachment: Attachment, authToken: String, completion: @escaping (_ result: Swift.Result<URL, Error>) -> ()){
        guard let url = URLStore.downloadAttachmentURL(attachment.id, authToken: authToken) else {
            LoggerManager.log("Failed in Download Attachment URL Creation")
            completion(.failure(DriftError.apiFailure))
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("bearer \(authToken)", forHTTPHeaderField: "Authorization")
        
        sharedManager.download(request).response { (response) in
            
            if let response = response.response {
                LoggerManager.log("API Complete: \(response.statusCode) \(response.url?.path ?? "")")
            }
            
            switch response.result {
                case .success(let url):
                    if let fileURL = url {
                        completion(.success(fileURL))
                    } else {
                        completion(.failure(DriftError.dataCreationFailure))
                    }
                case .failure(let error):
                    completion(.failure(error))
            }
        }
    }
    
    class func getAttachmentsMetaData(_ attachmentIds: [Int64], authToken: String, completion: @escaping (_ result: Swift.Result<[Attachment], Error>) -> ()){
        
        guard let url = URLStore.getAttachmentsURL(attachmentIds, authToken: authToken) else {
            LoggerManager.log("Failed in Get Attachment Metadata URL Creation")
            return
        }
        
        sharedManager.request(URLRequest(url: url)).driftResponseDecodable(completionHandler: { (response: DataResponse<[AttachmentDTO], AFError>) in
            completion(mapResponseArr(response))
        })
    }
    
    class func postAttachment(_ attachment: AttachmentPayload, authToken: String, completion: @escaping (_ result: Result<Attachment>) ->()){

        let boundary = "Boundary-\(UUID().uuidString)"
        let requestURL = URLStore.postAttachmentURL(authToken)
        
        let request = NSMutableURLRequest(url: requestURL!)
        
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        let multipartBody = NSMutableData()
        multipartBody.append("--\(boundary)\r\n".data(using: String.Encoding.utf8, allowLossyConversion: false)!)
        multipartBody.append("Content-Disposition: form-data; name=\"conversationId\"\r\n\r\n".data(using: String.Encoding.utf8, allowLossyConversion: false)!)
        multipartBody.append("\(attachment.conversationId)\r\n".data(using: String.Encoding.utf8, allowLossyConversion: false)!)
        
        multipartBody.append("--\(boundary)\r\n".data(using: String.Encoding.utf8, allowLossyConversion: false)!)
        multipartBody.append("Content-Disposition: form-data; name=\"file\"; filename=\"image.jpg\"\r\n".data(using: String.Encoding.utf8, allowLossyConversion: false)!)
        multipartBody.append("Content-Type: \(attachment.mimeType)\r\n\r\n".data(using: String.Encoding.utf8, allowLossyConversion: false)!)
        multipartBody.append(attachment.data as Data)
        multipartBody.append("\r\n".data(using: String.Encoding.utf8, allowLossyConversion: false)!)
        
        multipartBody.append("--\(boundary)--\r\n".data(using: String.Encoding.utf8, allowLossyConversion: false)!)
        request.httpBody = multipartBody as Data
        sharedManager.session.dataTask(with: request as URLRequest, completionHandler: { (data, response, error) in
            if let response = response as? HTTPURLResponse {
                LoggerManager.log("API Complete: \(response.statusCode) \(response.url?.path ?? "")")
            }
            
            let accepted = [200, 201]
            
            if let response = response as? HTTPURLResponse, let data = data , accepted.contains(response.statusCode){
                do {
                    let jsonDecoder = DriftAPIManager.jsonDecoder()
                    let attachmendDTO = try jsonDecoder.decode(AttachmentDTO.self, from: data)
                    if let attachment = attachmendDTO.mapToObject() {
                        DispatchQueue.main.async(execute: {
                              completion(.success(attachment))
                          })
                          return
                    } else {
                        DispatchQueue.main.async(execute: {
                            completion(.failure(DriftError.dataSerializationError))
                        })
                        return
                    }
                    
                } catch {
                    print(response.statusCode)
                    DispatchQueue.main.async(execute: {
                        completion(.failure(DriftError.apiFailure))
                    })
                }
            }else if let error = error {
                DispatchQueue.main.async(execute: {
                    completion(.failure(error))
                })
            }else{
                DispatchQueue.main.async(execute: {
                    completion(.failure(DriftError.apiFailure))
                })
            }
            
        }) .resume()
    }
    
    //Maps response to result T using Codable JSON parsing
    fileprivate class func mapResponse<T: DTO>(_ response: DataResponse<T, AFError>) -> Swift.Result<T.DataObject, Error> {
        
        switch response.result {
        case .success(let dto):
            if let obj = dto.mapToObject() {
                return .success(obj)
            } else {
                return .failure(DriftError.dataSerializationError)
            }
        case .failure(let error):
            return .failure(error)
        }
    }
    
    //Maps response array to result T using Codable JSON parsing
    fileprivate class func mapResponseArr<T: DTO>(_ response: DataResponse<[T], AFError>) -> Swift.Result<[T.DataObject], Error> {
        
        switch response.result {
        case .success(let dto):
            //if dto is empty return empty maping
            if dto.isEmpty {
                return .success([])
            } else {
                //If dto not empty parse and then if empty return error
                let objArr = dto.compactMap({$0.mapToObject()})
                
                if objArr.isEmpty {
                    //Parse Error
                    return .failure(DriftError.dataSerializationError)
                } else {
                    return .success(objArr)
                }
            }
        case .failure(let error):
            return .failure(error)
        }
    }
}

fileprivate extension DataRequest {

    @discardableResult
    func driftResponseDecodable<T: Decodable>(of type: T.Type = T.self,
                                                queue: DispatchQueue = .main,
                                                decoder: DataDecoder = DriftAPIManager.jsonDecoder(),
                                                completionHandler: @escaping (AFDataResponse<T>) -> Void) -> Self {
        return response(queue: queue,
                        responseSerializer: DecodableResponseSerializer(decoder: decoder),
                        completionHandler: completionHandler)
    }
}

class URLStore{
    
    class func postAttachmentURL(_ authToken: String) -> URL? {
        return URL(string: "https://conversation.api.drift.com/attachments?access_token=\(authToken)")
    }
    
    class func downloadAttachmentURL(_ attachmentId: Int64, authToken: String) -> URL? {
        return URL(string: "https://conversation.api.drift.com/attachments/\(attachmentId)/data?")
    }
    
    class func getAttachmentsURL(_ attachmentIds: [Int64], authToken: String) -> URL? {
        var params = ""
        for id in attachmentIds{
            params += "&id=\(id)"
        }
        params += "&img_auto=compress"

        return URL(string: "https://conversation.api.drift.com/attachments?access_token=\(authToken)\(params)")
    }
    
}

///Result object for either Success with sucessfully parsed T
enum Result<T> {
    case success(T)
    case failure(Error)
}
