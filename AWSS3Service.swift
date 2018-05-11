//
//  AWSS3Service.swift
//
//  Created by Sirichai Monhom on 4/25/18.
//  Copyright © 2018 Sirichai Monhom. All rights reserved.
//

import UIKit
import AWSS3
import AWSCore
import PromiseKit

extension AppEnvironment {
    static let S3BucketName = "S3BucketName"
    static let accessKey = "accessKey"
    static let secretKey = "secretKey"
}

protocol AWSS3Service {
    /**
     Url from S3 can not access direcly
     that url have to presigned before with AWSS3 SDK.
     @return URL is presigned  can be nil.
     */
    func getPreSignedURL(S3DownloadKeyPath: URL)-> URL?
    
    /**
     Wrap for easy to upload image to AWS S3
     */
    func uploadImageToS3(image:UIImage, imageName:String) -> Promise<URL>
    
    /**
     Wrap for easy to get file size from Metadata
     required s3 url for get filesize.
     @return Int64
     */
    func getFileSizefromS3Url(s3Url: URL) -> Promise<Int64>
}
class AWSS3Manager: NSObject, AWSS3Service {
    
    // MARK: - Shared Instance
    static let shared:AWSS3Service = {
        return AWSS3Manager()
    }()
    
    // MARK: - Initialization Method
    override internal init() {
        super.init()
        // Set up
        let credentialsProvider = AWSStaticCredentialsProvider(accessKey: AppEnvironment.accessKey, secretKey: AppEnvironment.secretKey)
        let configuration = AWSServiceConfiguration(region: AWSRegionType.APSoutheast1, credentialsProvider: credentialsProvider)
        AWSServiceManager.default().defaultServiceConfiguration = configuration
    }
    
    //
    func getPreSignedURL(S3DownloadKeyPath: URL)-> URL?{
        let getPreSignedURLRequest = AWSS3GetPreSignedURLRequest()
        getPreSignedURLRequest.httpMethod = AWSHTTPMethod.GET
        getPreSignedURLRequest.key = self.getKeyfromS3Url(url: S3DownloadKeyPath)
        getPreSignedURLRequest.bucket = AppEnvironment.S3BucketName
        getPreSignedURLRequest.expires = Date(timeIntervalSinceNow: 3600)
            
        
        let task = AWSS3PreSignedURLBuilder.default().getPreSignedURL(getPreSignedURLRequest)
        task.waitUntilFinished()
        return task.result?.absoluteURL
    }
    
    /**
     * extract s3 URL's key
     * S3 URL can be in 2 cases where bucketname is placed as subdomain.
     * case1 = "http://s3-southeast-1.amazonaws.com/S3BucketName/profile_image/3.png"
     * case2 = "http://S3BucketName.s3-southeast-1.amazonaws.com/profile_image/3.png"
     */
    func getKeyfromS3Url(url:URL) -> String{
        
        let urlString = url.absoluteString
        // case1 bucket is in the path of URL (s3.)
        if url.absoluteString.range(of:"://s3-ap-southeast-1") == nil  {
            return urlString.removingRegexMatches(patternRegx:"^[^/]*\\/\\/[^/]*\\/")
        }
        // case2 bucket is a subdomain.
        else{
            return urlString.removingRegexMatches(patternRegx:"^[^/]*\\/\\/[^/]*\\/[^/]*\\/")
        }
    }
    
    func getFileSizefromS3Url(s3Url: URL) -> Promise<Int64>{
        return Promise { (fullfill, reject) in
            let request = AWSS3HeadObjectRequest()!
            request.key = self.getKeyfromS3Url(url: s3Url)
            request.bucket = AppEnvironment.S3BucketName
            
            let s3 = AWSS3.default()
            s3.headObject(request) {
                (output1 : AWSS3HeadObjectOutput?, error : Error?) -> Void in
                if let error  =  error{
                    error.log()
                    reject(error)
                } else {
                    if let contentLength = output1?.contentLength{
                        fullfill(contentLength.int64Value)
                    }
                }
            }
        }
    }

    
    func uploadImageToS3(image:UIImage, imageName:String) -> Promise<URL>{
        return Promise { (fullfill, reject) in
            let toPath = "profile_images/" + imageName
            let fileManager = FileManager.default
            let path = (NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] as NSString).appendingPathComponent(imageName)
            let imageData = UIImageJPEGRepresentation(image, 0.5)
            fileManager.createFile(atPath: path as String, contents: imageData, attributes: nil)
            
            let fileUrl = NSURL(fileURLWithPath: path)
            let uploadRequest = AWSS3TransferManagerUploadRequest()
            uploadRequest?.bucket = AppEnvironment.S3BucketName
            uploadRequest?.key = toPath
            uploadRequest?.contentType = "image/jpeg"
            uploadRequest?.body = fileUrl as URL!
            uploadRequest?.serverSideEncryption = AWSS3ServerSideEncryption.awsKms
            
            /*
             uploadRequest?.uploadProgress = { (bytesSent, totalBytesSent, totalBytesExpectedToSend) -> Void in
             DispatchQueue.main.async(execute: {
             
             })
             }
             */
            
            let transferManager = AWSS3TransferManager.default()
            transferManager.upload(uploadRequest!).continueWith(executor: AWSExecutor.mainThread(), block: { (task:AWSTask<AnyObject>) -> Any? in
                if let error = task.error  {
                    reject(error)
                } else {
                    // Upload to AWS S3 Success
                    let url = AWSS3.default().configuration.endpoint.url
                    if let fileURL = url?.appendingPathComponent(uploadRequest?.bucket ?? AppEnvironment.S3BucketName).appendingPathComponent(uploadRequest?.key ?? toPath){
                        fullfill(fileURL)
                    }
                    else{
                        reject(RocheError.default(debugMessage: "UploadImageToS3 fileURL not ready"))
                    }
                }
                return nil
            })
        }
    }
}
/**
 Detect url from AWS S3
 */
extension URL {
    func isAWSS3Url() -> Bool{
        if self.absoluteString.range(of:"ap-southeast-1.amazonaws.com") != nil {
            return true
        }
        
        return false
    }
}

private extension String {
    func removingRegexMatches(patternRegx:String) -> String{
        let regex = try! NSRegularExpression(pattern:patternRegx, options: NSRegularExpression.Options.caseInsensitive)
        let range = NSMakeRange(0, self.count)
        return  regex.stringByReplacingMatches(in: self, options: [], range: range, withTemplate: "")
    }
}
