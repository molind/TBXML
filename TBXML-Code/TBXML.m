// ================================================================================================
//  TBXML.m
//  Fast processing of XML files
//
// ================================================================================================
//  Created by Tom Bradley on 21/10/2009.
//  Version 1.5
//  
//  Copyright 2012 71Squared All rights reserved.
//  
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//  
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//  
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
// ================================================================================================
#import "TBXML.h"

// ================================================================================================
// Private methods
// ================================================================================================
@interface TBXML (Private)
+ (NSString *) errorTextForCode:(int)code;
+ (NSError *) errorWithCode:(int)code;
+ (NSError *) errorWithCode:(int)code userInfo:(NSDictionary *)userInfo;
- (void) decodeBytes;
- (void) allocateBytesOfLength:(long)length error:(NSError **)error;
- (TBXMLElement*) nextAvailableElement;
- (TBXMLAttribute*) nextAvailableAttribute;
@end

// ================================================================================================
// Public Implementation
// ================================================================================================
@implementation TBXML

@synthesize rootXMLElement;

+ (id)tbxmlWithXMLString:(NSString*)aXMLString {
	return [[TBXML alloc] initWithXMLString:aXMLString];
}

+ (id)tbxmlWithXMLString:(NSString*)aXMLString error:(NSError *__autoreleasing *)error {
	return [[TBXML alloc] initWithXMLString:aXMLString error:error];
}

+ (id)tbxmlWithXMLData:(NSData*)aData {
	return [[TBXML alloc] initWithXMLData:aData];
}

+ (id)tbxmlWithXMLData:(NSData*)aData error:(NSError *__autoreleasing *)error {
	return [[TBXML alloc] initWithXMLData:aData error:error];
}

+ (id)tbxmlWithXMLFile:(NSString*)aXMLFile {
	return [[TBXML alloc] initWithXMLFile:aXMLFile];
}

+ (id)tbxmlWithXMLFile:(NSString*)aXMLFile error:(NSError *__autoreleasing *)error {
	return [[TBXML alloc] initWithXMLFile:aXMLFile error:error];
}

+ (id)tbxmlWithXMLFile:(NSString*)aXMLFile fileExtension:(NSString*)aFileExtension {
	return [[TBXML alloc] initWithXMLFile:aXMLFile fileExtension:aFileExtension];
}

+ (id)tbxmlWithXMLFile:(NSString*)aXMLFile fileExtension:(NSString*)aFileExtension error:(NSError *__autoreleasing *)error {
	return [[TBXML alloc] initWithXMLFile:aXMLFile fileExtension:aFileExtension error:error];
}

- (id)init {
	self = [super init];
	if (self != nil) {
		rootXMLElement = nil;
		
		currentElementBuffer = 0;
		currentAttributeBuffer = 0;
		
		currentElement = 0;
		currentAttribute = 0;		
		
		bytes = 0;
		bytesLength = 0;
	}
	return self;
}
- (id)initWithXMLString:(NSString*)aXMLString {
    return [self initWithXMLString:aXMLString error:nil];
}

- (id)initWithXMLString:(NSString*)aXMLString error:(NSError *__autoreleasing *)error {
	self = [self init];
	if (self != nil) {
		
        
        // allocate memory for byte array
        [self allocateBytesOfLength:[aXMLString lengthOfBytesUsingEncoding:NSUTF8StringEncoding] error:error];
        
        // if an error occured, return
        if (error && *error != nil) 
            return self;
        
		// copy string to byte array
		[aXMLString getBytes:bytes maxLength:bytesLength usedLength:0 encoding:NSUTF8StringEncoding options:NSStringEncodingConversionAllowLossy range:NSMakeRange(0, bytesLength) remainingRange:nil];
		
		// set null terminator at end of byte array
		bytes[bytesLength] = 0;
		
		// decode xml data
		[self decodeBytes];
        
        // Check for root element
        if (error && !*error && !self.rootXMLElement) {
            *error = [TBXML errorWithCode:D_TBXML_DECODE_FAILURE];
        }
	}
	return self;
}

- (id)initWithXMLData:(NSData*)aData {
    return [self initWithXMLData:aData error:nil];
}

- (id)initWithXMLData:(NSData*)aData error:(NSError **)error {
    self = [self init];
    if (self != nil) {
		// decode aData
        if (!aData || [aData length] == 0) {
            return nil;
        }
        
		[self decodeData:aData withError:error];
    }
    
    return self;
}

- (id)initWithXMLFile:(NSString*)aXMLFile {
    return [self initWithXMLFile:aXMLFile error:nil];
}

- (id)initWithXMLFile:(NSString*)aXMLFile error:(NSError **)error {
    NSString * filename = [aXMLFile stringByDeletingPathExtension];
    NSString * extension = [aXMLFile pathExtension];
    
    self = [self initWithXMLFile:filename fileExtension:extension error:error];
	if (self != nil) {
        
	}
	return self;
}

- (id)initWithXMLFile:(NSString*)aXMLFile fileExtension:(NSString*)aFileExtension {
    return [self initWithXMLFile:aXMLFile fileExtension:aFileExtension error:nil];
}

- (id)initWithXMLFile:(NSString*)aXMLFile fileExtension:(NSString*)aFileExtension error:(NSError **)error {
	self = [self init];
	if (self != nil) {
        
        NSData * data;
        
        // Get the bundle that this class resides in. This allows to load resources from the app bundle when running unit tests.
        NSString * bundlePath = [[NSBundle bundleForClass:[self class]] pathForResource:aXMLFile ofType:aFileExtension];

        if (!bundlePath) {
            if (error) {
                NSDictionary * userInfo = [NSDictionary dictionaryWithObjectsAndKeys:[aXMLFile stringByAppendingPathExtension:aFileExtension], NSFilePathErrorKey, nil];
                *error = [TBXML errorWithCode:D_TBXML_FILE_NOT_FOUND_IN_BUNDLE userInfo:userInfo];
            }
        } else {
            SEL dataWithUncompressedContentsOfFile = NSSelectorFromString(@"dataWithUncompressedContentsOfFile:");
            
            // Get uncompressed file contents if TBXML+Compression has been included
            if ([[NSData class] respondsToSelector:dataWithUncompressedContentsOfFile]) {
                
                #pragma clang diagnostic push
                #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                data = [[NSData class] performSelector:dataWithUncompressedContentsOfFile withObject:bundlePath];
                #pragma clang diagnostic pop   

            } else {
                data = [NSData dataWithContentsOfFile:bundlePath];
            }
            
            // decode data
            [self decodeData:data withError:error];
            
            // Check for root element
            if (error && !*error && !self.rootXMLElement) {
                *error = [TBXML errorWithCode:D_TBXML_DECODE_FAILURE];
            }
        }
	}
	return self;
}

- (void) decodeData:(NSData*)data {
    [self decodeData:data withError:nil];
}

- (void) decodeData:(NSData*)data withError:(NSError **)error {
    
    if ([data length] >= 4) {
        unsigned char bom[4];
        [data getBytes:bom length:sizeof(bom)];
        if (bom[0] == 0xFE && bom[1] == 0xFF) { // is utf-16 BE
            NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF16BigEndianStringEncoding];
            data = [str dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];
        } else if (bom[0] == 0xFF && bom[1] == 0xFE) { // is utf-16 LE
            NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF16LittleEndianStringEncoding];
            data = [str dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];
        } else if (bom[0] == 0 && bom[1] == 0x0 && bom[2] == 0xFE && bom[3] == 0xFF) { // is utf-32 BE
            NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF32BigEndianStringEncoding];
            data = [str dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];
        } else if (bom[0] == 0xFF && bom[1] == 0xFE && bom[2] == 0 && bom[3] == 0) { // is utf-32 LE
            NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF32LittleEndianStringEncoding];
            data = [str dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];
        }
    }
    
    // allocate memory for byte array
    [self allocateBytesOfLength:[data length] error:error];

    // if an error occured, return
    if (error && *error)
        return;
    
    // copy data to byte array
    [data getBytes:bytes length:bytesLength];
    
	// set null terminator at end of byte array
	bytes[bytesLength] = 0;
	
	// decode xml data
	[self decodeBytes];
    
    if (!self.rootXMLElement && error) {
        *error = [TBXML errorWithCode:D_TBXML_DECODE_FAILURE];
    }
}

@end


// ================================================================================================
// Static Functions Implementation
// ================================================================================================

#pragma mark -
#pragma mark Static Functions implementation

@implementation TBXML (FastNameCompare)

+ (BOOL) isElementName:(TBXMLElement *)aXMLElement equalToCString:(const char *)aCString {
    return (strcmp(aXMLElement->name, aCString) == 0);
}

@end

@implementation TBXML (StaticFunctions)

+ (NSString*) elementName:(TBXMLElement*)aXMLElement {
	if (nil == aXMLElement->name) return @"";
	return [NSString stringWithCString:&aXMLElement->name[0] encoding:NSUTF8StringEncoding];
}

+ (NSString*) elementName:(TBXMLElement*)aXMLElement error:(NSError **)error {
    // check for nil element
    if (nil == aXMLElement) {
        if (error)
            *error = [TBXML errorWithCode:D_TBXML_ELEMENT_IS_NIL];
        return @"";
    }
    
    // check for nil element name
    if (nil == aXMLElement->name || strlen(aXMLElement->name) == 0) {
        if (error)
            *error = [TBXML errorWithCode:D_TBXML_ELEMENT_NAME_IS_NIL];
        return @"";
    }
    
	return [NSString stringWithCString:&aXMLElement->name[0] encoding:NSUTF8StringEncoding];
}

+ (NSString*) attributeName:(TBXMLAttribute*)aXMLAttribute {
	if (nil == aXMLAttribute->name) return @"";
	return [NSString stringWithCString:&aXMLAttribute->name[0] encoding:NSUTF8StringEncoding];
}

+ (NSString*) attributeName:(TBXMLAttribute*)aXMLAttribute error:(NSError **)error {
    // check for nil attribute
    if (nil == aXMLAttribute) {
        if (error)
            *error = [TBXML errorWithCode:D_TBXML_ATTRIBUTE_IS_NIL];
        return @"";
    }
    
    // check for nil attribute name
    if (nil == aXMLAttribute->name) {
        if (error)
            *error = [TBXML errorWithCode:D_TBXML_ATTRIBUTE_NAME_IS_NIL];
        return @"";
    }
    
	return [NSString stringWithCString:&aXMLAttribute->name[0] encoding:NSUTF8StringEncoding];
}


+ (NSString*) attributeValue:(TBXMLAttribute*)aXMLAttribute {
	if (nil == aXMLAttribute->value) return @"";
	return [NSString stringWithCString:&aXMLAttribute->value[0] encoding:NSUTF8StringEncoding];
}

+ (NSString*) attributeValue:(TBXMLAttribute*)aXMLAttribute error:(NSError **)error {
    // check for nil attribute
    if (nil == aXMLAttribute) {
        if (error)
            *error = [TBXML errorWithCode:D_TBXML_ATTRIBUTE_IS_NIL];
        return @"";
    }
    
	return [NSString stringWithCString:&aXMLAttribute->value[0] encoding:NSUTF8StringEncoding];
}

+ (NSString*) textForElement:(TBXMLElement*)aXMLElement {
	NSString *str = nil;
    
    if (nil == aXMLElement || nil == aXMLElement->text) 
        return str;
    
    if (aXMLElement->text[0]) {
        str = [NSString stringWithCString:&aXMLElement->text[0] encoding:NSUTF8StringEncoding];
    
        if (!str) {
            str = [NSString stringWithCString:&aXMLElement->text[0] encoding:NSISOLatin1StringEncoding];    
        }
    }
    
    return str;
}

+ (NSString*) textForElement:(TBXMLElement*)aXMLElement error:(NSError **)error {
    // check for nil element
    if (nil == aXMLElement) {
        if (error)
            *error = [TBXML errorWithCode:D_TBXML_ELEMENT_IS_NIL];
        return @"";
    }
    
    // check for nil text value
    if (nil == aXMLElement->text || strlen(aXMLElement->text) == 0) {
        if (error)
            *error = [TBXML errorWithCode:D_TBXML_ELEMENT_TEXT_IS_NIL];
        return @"";
    }
    
	return [NSString stringWithCString:&aXMLElement->text[0] encoding:NSUTF8StringEncoding];
}

+ (NSString*) valueOfAttributeNamed:(NSString *)aName forElement:(TBXMLElement*)aXMLElement {
	const char * name = [aName cStringUsingEncoding:NSUTF8StringEncoding];
	NSString * value = nil;
	TBXMLAttribute * attribute = aXMLElement->firstAttribute;
	while (attribute) {
		if (strcmp(attribute->name,name) == 0) {
			value = [NSString stringWithCString:&attribute->value[0] encoding:NSUTF8StringEncoding];
			break;
		}
		attribute = attribute->next;
	}
	return value;
}

+ (NSString*) valueOfAttributeNamed:(NSString *)aName forElement:(TBXMLElement*)aXMLElement error:(NSError **)error {
    // check for nil element
    if (nil == aXMLElement) {
        if (error)
            *error = [TBXML errorWithCode:D_TBXML_ELEMENT_IS_NIL];
        return @"";
    }
    
    // check for nil name parameter
    if (nil == aName) {
        if (error)
            *error = [TBXML errorWithCode:D_TBXML_ATTRIBUTE_NAME_IS_NIL];
        return @"";
    }
    
	const char * name = [aName cStringUsingEncoding:NSUTF8StringEncoding];
	NSString * value = nil;
    
	TBXMLAttribute * attribute = aXMLElement->firstAttribute;
	while (attribute) {
		if (strcmp(attribute->name,name) == 0) {
            if (attribute->value[0])
                value = [NSString stringWithCString:&attribute->value[0] encoding:NSUTF8StringEncoding];
			break;
		}
		attribute = attribute->next;
	}
    
    // check for attribute not found
    if (!value) {
        if (error)
            *error = [TBXML errorWithCode:D_TBXML_ATTRIBUTE_NOT_FOUND];
        return @"";
    }
    
	return value;
}

+ (TBXMLElement*) childElementNamed:(NSString*)aName parentElement:(TBXMLElement*)aParentXMLElement{
    if (!aParentXMLElement)
        return nil;
    
	TBXMLElement * xmlElement = aParentXMLElement->firstChild;
	const char * name = [aName cStringUsingEncoding:NSUTF8StringEncoding];
	while (xmlElement) {
		if (strcmp(name, xmlElement->name)==0) {
			return xmlElement;
		}
		xmlElement = xmlElement->nextSibling;
	}
	return nil;
}

+ (TBXMLElement*) childElementNamed:(NSString*)aName parentElement:(TBXMLElement*)aParentXMLElement error:(NSError **)error {
    // check for nil element
    if (nil == aParentXMLElement) {
        if (error)
            *error = [TBXML errorWithCode:D_TBXML_ELEMENT_IS_NIL];
        return nil;
    }
    
    // check for nil name parameter
    if (nil == aName) {
        if (error)
            *error = [TBXML errorWithCode:D_TBXML_PARAM_NAME_IS_NIL];
        return nil;
    }
    
	TBXMLElement * xmlElement = aParentXMLElement->firstChild;
	const char * name = [aName cStringUsingEncoding:NSUTF8StringEncoding];
	while (xmlElement) {
		if (strcmp(xmlElement->name,name) == 0) {
			return xmlElement;
		}
		xmlElement = xmlElement->nextSibling;
	}
    
    if (error)
        *error = [TBXML errorWithCode:D_TBXML_ELEMENT_NOT_FOUND];
    
	return nil;
}

+ (TBXMLElement*) nextSiblingNamed:(NSString*)aName searchFromElement:(TBXMLElement*)aXMLElement{
	TBXMLElement * xmlElement = aXMLElement->nextSibling;
	const char * name = [aName cStringUsingEncoding:NSUTF8StringEncoding];
	while (xmlElement) {
		if (strcmp(xmlElement->name,name) == 0) {
			return xmlElement;
		}
		xmlElement = xmlElement->nextSibling;
	}
	return nil;
}

+ (TBXMLElement*) nextSiblingNamed:(NSString*)aName searchFromElement:(TBXMLElement*)aXMLElement error:(NSError **)error {
    // check for nil element
    if (nil == aXMLElement) {
        if (error)
            *error = [TBXML errorWithCode:D_TBXML_ELEMENT_IS_NIL];
        return nil;
    }
    
    // check for nil name parameter
    if (nil == aName) {
        if (error)
            *error = [TBXML errorWithCode:D_TBXML_PARAM_NAME_IS_NIL];
        return nil;
    }
    
	TBXMLElement * xmlElement = aXMLElement->nextSibling;
	const char * name = [aName cStringUsingEncoding:NSUTF8StringEncoding];
	while (xmlElement) {
		if (strcmp(xmlElement->name,name) == 0) {
			return xmlElement;
		}
		xmlElement = xmlElement->nextSibling;
	}
    
    if (error)
        *error = [TBXML errorWithCode:D_TBXML_ELEMENT_NOT_FOUND];
    
	return nil;
}

+ (void)iterateElementsForQuery:(NSString *)query fromElement:(TBXMLElement *)anElement withBlock:(TBXMLIterateBlock)iterateBlock {
    
    NSArray *components = [query componentsSeparatedByString:@"."];
    TBXMLElement *currTBXMLElement = anElement;
    
    // navigate down
    for (NSInteger i=0; i < components.count; ++i) {
        NSString *iTagName = [components objectAtIndex:i];
        
        if ([iTagName isEqualToString:@"*"]) {
            currTBXMLElement = currTBXMLElement->firstChild;
            
            // different behavior depending on if this is the end of the query or midstream
            if (i < (components.count - 1)) {
                // midstream
                do {
                    NSString *restOfQuery = [[components subarrayWithRange:NSMakeRange(i + 1, components.count - i - 1)] componentsJoinedByString:@"."];
                    [TBXML iterateElementsForQuery:restOfQuery fromElement:currTBXMLElement withBlock:iterateBlock];
                } while ((currTBXMLElement = currTBXMLElement->nextSibling));
                
            }
        } else {
            currTBXMLElement = [TBXML childElementNamed:iTagName parentElement:currTBXMLElement];            
        }
        
        if (!currTBXMLElement) {
            break;
        }
    }
    
    if (currTBXMLElement) {
        // enumerate
        NSString *childTagName = [components lastObject];
        
        if ([childTagName isEqualToString:@"*"]) {
            childTagName = nil;
        }
        
        do {
            iterateBlock(currTBXMLElement);
        } while ((currTBXMLElement = currTBXMLElement->nextSibling));
    }
}

+ (void)iterateAttributesOfElement:(TBXMLElement *)anElement withBlock:(TBXMLIterateAttributeBlock)iterateAttributeBlock {

    // Obtain first attribute from element
    TBXMLAttribute * attribute = anElement->firstAttribute;
    
    // if attribute is valid
    
    while (attribute) {
        // Call the iterateAttributeBlock with the attribute, it's name and value
        iterateAttributeBlock(attribute, [TBXML attributeName:attribute], [TBXML attributeValue:attribute]);
        
        // Obtain the next attribute
        attribute = attribute->next;
    }
}

@end


// ================================================================================================
// Private Implementation
// ================================================================================================

#pragma mark -
#pragma mark Private implementation

@implementation TBXML (Private)

+ (NSString *) errorTextForCode:(int)code {
    NSString * codeText = @"";
    
    switch (code) {
        case D_TBXML_DATA_NIL:                  codeText = @"Data is nil";                          break;
        case D_TBXML_DECODE_FAILURE:            codeText = @"Decode failure";                       break;
        case D_TBXML_MEMORY_ALLOC_FAILURE:      codeText = @"Unable to allocate memory";            break;
        case D_TBXML_FILE_NOT_FOUND_IN_BUNDLE:  codeText = @"File not found in bundle";             break;
            
        case D_TBXML_ELEMENT_IS_NIL:            codeText = @"Element is nil";                       break;
        case D_TBXML_ELEMENT_NAME_IS_NIL:       codeText = @"Element name is nil";                  break;
        case D_TBXML_ATTRIBUTE_IS_NIL:          codeText = @"Attribute is nil";                     break;
        case D_TBXML_ATTRIBUTE_NAME_IS_NIL:     codeText = @"Attribute name is nil";                break;
        case D_TBXML_ELEMENT_TEXT_IS_NIL:       codeText = @"Element text is nil";                  break;
        case D_TBXML_PARAM_NAME_IS_NIL:         codeText = @"Parameter name is nil";                break;
        case D_TBXML_ATTRIBUTE_NOT_FOUND:       codeText = @"Attribute not found";                  break;
        case D_TBXML_ELEMENT_NOT_FOUND:         codeText = @"Element not found";                    break;
            
        default: codeText = @"No Error Description!"; break;
    }
    
    return codeText;
}

+ (NSError *) errorWithCode:(int)code {
    
    NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:[TBXML errorTextForCode:code], NSLocalizedDescriptionKey, nil];
    
    return [NSError errorWithDomain:D_TBXML_DOMAIN 
                               code:code 
                           userInfo:userInfo];
}

+ (NSError *) errorWithCode:(int)code userInfo:(NSMutableDictionary *)someUserInfo {
    
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:someUserInfo];
    [userInfo setValue:[TBXML errorTextForCode:code] forKey:NSLocalizedDescriptionKey];
    
    return [NSError errorWithDomain:D_TBXML_DOMAIN 
                               code:code 
                           userInfo:userInfo];
}

- (void) allocateBytesOfLength:(long)length error:(NSError **)error {
    bytesLength = length;
    
    if(!length && error) {
        *error = [TBXML errorWithCode:D_TBXML_DATA_NIL];
    }
    
	bytes = malloc(bytesLength+1);
    
    if(!bytes && error) {
        *error = [TBXML errorWithCode:D_TBXML_MEMORY_ALLOC_FAILURE];
    }
}

- (void) decodeBytes {
	
	// -----------------------------------------------------------------------------
	// Process xml
	// -----------------------------------------------------------------------------
	
	// set elementStart pointer to the start of our xml
	char * elementStart=bytes;
    char * stringEnd = elementStart + bytesLength;
	
	// set parent element to nil
	TBXMLElement * parentXMLElement = nil;

	// find next element start
	while ((elementStart = strnstr(elementStart,"<", stringEnd-elementStart))) {
		
		// detect comment section
		if (strncmp(elementStart,"<!--",4) == 0) {
			elementStart = strnstr(elementStart,"-->", stringEnd-elementStart) + 3;
			continue;
		}

		// detect cdata section within element text
		int isCDATA = strncmp(elementStart,"<![CDATA[",9);
		
		// if cdata section found, skip data within cdata section and remove cdata tags
		if (isCDATA==0) {
			
			// find end of cdata section
			char * CDATAEnd = strnstr(elementStart,"]]>", stringEnd-elementStart);
			
			// find start of next element skipping any cdata sections within text
			char * elementEnd = CDATAEnd;
			
			// find next open tag
			elementEnd = strnstr(elementEnd,"<", stringEnd-elementEnd);
			// if open tag is a cdata section
			while (strncmp(elementEnd,"<![CDATA[",9) == 0) {
				// find end of cdata section
				elementEnd = strnstr(elementEnd,"]]>", stringEnd-elementEnd);
				// find next open tag
				elementEnd = strnstr(elementEnd,"<", stringEnd-elementEnd);
			}
			
			// calculate length of cdata content
			long CDATALength = CDATAEnd-elementStart;
			
			// calculate total length of text
			long textLength = elementEnd-elementStart;
			
			// remove begining cdata section tag
			memmove(elementStart, elementStart+9, CDATAEnd-elementStart-9);

			// remove ending cdata section tag
			memmove(CDATAEnd-9, CDATAEnd+3, textLength-CDATALength-3);
			
			// blank out end of text
			memset(elementStart+textLength-12,' ',12);
			
			// set new search start position 
			elementStart = CDATAEnd-9;
			continue;
		}
		
		
		// find element end, skipping any cdata sections within attributes
		char * elementEnd = elementStart+1;		
		while ((elementEnd = strpbrk(elementEnd, "<>"))) {
			if (strncmp(elementEnd,"<![CDATA[",9) == 0) {
				elementEnd = strnstr(elementEnd,"]]>", stringEnd-elementEnd)+3;
			} else {
				break;
			}
		}
		
        if (!elementEnd) break;
		
		// null terminate element end
		if (elementEnd) *elementEnd = 0;
		
		// null terminate element start so previous element text doesnt overrun
		*elementStart = 0;
		
		// get element name start
		char * elementNameStart = elementStart+1;
		
		// ignore tags that start with ? or ! unless cdata "<![CDATA"
		if (*elementNameStart == '?' || (*elementNameStart == '!' && isCDATA != 0)) {
			elementStart = elementEnd+1;
			continue;
		}
		
		// ignore attributes/text if this is a closing element
		if (*elementNameStart == '/') {
			elementStart = elementEnd+1;
			if (parentXMLElement) {

				if (parentXMLElement->text) {
					// trim whitespace from start of text
					while (isspace(*parentXMLElement->text)) 
						parentXMLElement->text++;
					
					// trim whitespace from end of text
					char * end = parentXMLElement->text + strlen(parentXMLElement->text)-1;
					while (end > parentXMLElement->text && isspace(*end)) 
						*end--=0;
				}
				
				parentXMLElement = parentXMLElement->parentElement;
				
				// if parent element has children clear text
				if (parentXMLElement && parentXMLElement->firstChild)
					parentXMLElement->text = 0;
				
			}
			continue;
		}
		
		
		// is this element opening and closing
		BOOL selfClosingElement = NO;
		if (*(elementEnd-1) == '/') {
			selfClosingElement = YES;
		}
		
		
		// create new xmlElement struct
		TBXMLElement * xmlElement = [self nextAvailableElement];
		
		// set element name
		xmlElement->name = elementNameStart;
		
		// if there is a parent element
		if (parentXMLElement) {
			
			// if this is first child of parent element
			if (parentXMLElement->currentChild) {
				// set next child element in list
				parentXMLElement->currentChild->nextSibling = xmlElement;
				xmlElement->previousSibling = parentXMLElement->currentChild;
				
				parentXMLElement->currentChild = xmlElement;
				
				
			} else {
				// set first child element
				parentXMLElement->currentChild = xmlElement;
				parentXMLElement->firstChild = xmlElement;
			}
			
			xmlElement->parentElement = parentXMLElement;
		}
		
		
		// in the following xml the ">" is replaced with \0 by elementEnd. 
		// element may contain no atributes and would return nil while looking for element name end
		// <tile> 
		// find end of element name
		char * elementNameEnd = strpbrk(xmlElement->name," /\n\r");
		
		// if end was found check for attributes
		if (elementNameEnd) {
			
			// null terminate end of elemenet name
			*elementNameEnd = 0;
			
			char * chr = elementNameEnd;
			char * name = nil;
			char * value = nil;
			char * CDATAStart = nil;
			char * CDATAEnd = nil;
			TBXMLAttribute * lastXMLAttribute = nil;
			TBXMLAttribute * xmlAttribute = nil;
			BOOL singleQuote = NO;
			
			int mode = TBXML_ATTRIBUTE_NAME_START;
			
			// loop through all characters within element
			while (chr++ < elementEnd) {
				
				switch (mode) {
					// look for start of attribute name
					case TBXML_ATTRIBUTE_NAME_START:
						if (isspace(*chr)) continue;
						name = chr;
						mode = TBXML_ATTRIBUTE_NAME_END;
						break;
					// look for end of attribute name
					case TBXML_ATTRIBUTE_NAME_END:
						if (isspace(*chr) || *chr == '=') {
							*chr = 0;
							mode = TBXML_ATTRIBUTE_VALUE_START;
						}
						break;
					// look for start of attribute value
					case TBXML_ATTRIBUTE_VALUE_START:
						if (isspace(*chr)) continue;
						if (*chr == '"' || *chr == '\'') {
							value = chr+1;
							mode = TBXML_ATTRIBUTE_VALUE_END;
							if (*chr == '\'') 
								singleQuote = YES;
							else
								singleQuote = NO;
						}
						break;
					// look for end of attribute value
					case TBXML_ATTRIBUTE_VALUE_END:
						if (*chr == '<' && strncmp(chr, "<![CDATA[", 9) == 0) {
							mode = TBXML_ATTRIBUTE_CDATA_END;
						}else if ((*chr == '"' && singleQuote == NO) || (*chr == '\'' && singleQuote == YES)) {
							*chr = 0;
							
							// remove cdata section tags
							while ((CDATAStart = strstr(value, "<![CDATA["))) {
								
								// remove begin cdata tag
								memcpy(CDATAStart, CDATAStart+9, strlen(CDATAStart)-8);
								
								// search for end cdata
								CDATAEnd = strstr(CDATAStart,"]]>");
								
								// remove end cdata tag
								memcpy(CDATAEnd, CDATAEnd+3, strlen(CDATAEnd)-2);
							}
							
							
							// create new attribute
							xmlAttribute = [self nextAvailableAttribute];
							
							// if this is the first attribute found, set pointer to this attribute on element
							if (!xmlElement->firstAttribute) xmlElement->firstAttribute = xmlAttribute;
							// if previous attribute found, link this attribute to previous one
							if (lastXMLAttribute) lastXMLAttribute->next = xmlAttribute;
							// set last attribute to this attribute
							lastXMLAttribute = xmlAttribute;

							// set attribute name & value
							xmlAttribute->name = name;
							xmlAttribute->value = value;
							
							// clear name and value pointers
							name = nil;
							value = nil;
							
							// start looking for next attribute
							mode = TBXML_ATTRIBUTE_NAME_START;
						}
						break;
						// look for end of cdata
					case TBXML_ATTRIBUTE_CDATA_END:
						if (*chr == ']') {
							if (strncmp(chr, "]]>", 3) == 0) {
								mode = TBXML_ATTRIBUTE_VALUE_END;
							}
						}
						break;						
					default:
						break;
				}
			}
		}
		
		// if tag is not self closing, set parent to current element
		if (!selfClosingElement) {
			// set text on element to element end+1
			if (*(elementEnd+1) != '>')
				xmlElement->text = elementEnd+1;
			
			parentXMLElement = xmlElement;
		}
		
		// start looking for next element after end of current element
		elementStart = elementEnd+1;
	}
}

// Deallocate used memory
- (void) dealloc {
	
	if (bytes) {
		free(bytes);
		bytes = nil;
	}
	
	while (currentElementBuffer) {
		if (currentElementBuffer->elements)
			free(currentElementBuffer->elements);
		
		if (currentElementBuffer->previous) {
			currentElementBuffer = currentElementBuffer->previous;
			free(currentElementBuffer->next);
		} else {
			free(currentElementBuffer);
			currentElementBuffer = 0;
		}
	}
	
	while (currentAttributeBuffer) {
		if (currentAttributeBuffer->attributes)
			free(currentAttributeBuffer->attributes);
		
		if (currentAttributeBuffer->previous) {
			currentAttributeBuffer = currentAttributeBuffer->previous;
			free(currentAttributeBuffer->next);
		} else {
			free(currentAttributeBuffer);
			currentAttributeBuffer = 0;
		}
	}
	
}

- (TBXMLElement*) nextAvailableElement {
	currentElement++;
	
	if (!currentElementBuffer) {
		currentElementBuffer = calloc(1, sizeof(TBXMLElementBuffer));
		currentElementBuffer->elements = (TBXMLElement*)calloc(1,sizeof(TBXMLElement)*MAX_ELEMENTS);
		currentElement = 0;
		rootXMLElement = &currentElementBuffer->elements[currentElement];
	} else if (currentElement >= MAX_ELEMENTS) {
		currentElementBuffer->next = calloc(1, sizeof(TBXMLElementBuffer));
		currentElementBuffer->next->previous = currentElementBuffer;
		currentElementBuffer = currentElementBuffer->next;
		currentElementBuffer->elements = (TBXMLElement*)calloc(1,sizeof(TBXMLElement)*MAX_ELEMENTS);
		currentElement = 0;
	}
	
	return &currentElementBuffer->elements[currentElement];
}

- (TBXMLAttribute*) nextAvailableAttribute {
	currentAttribute++;
	
	if (!currentAttributeBuffer) {
		currentAttributeBuffer = calloc(1, sizeof(TBXMLAttributeBuffer));
		currentAttributeBuffer->attributes = (TBXMLAttribute*)calloc(MAX_ATTRIBUTES,sizeof(TBXMLAttribute));
		currentAttribute = 0;
	} else if (currentAttribute >= MAX_ATTRIBUTES) {
		currentAttributeBuffer->next = calloc(1, sizeof(TBXMLAttributeBuffer));
		currentAttributeBuffer->next->previous = currentAttributeBuffer;
		currentAttributeBuffer = currentAttributeBuffer->next;
		currentAttributeBuffer->attributes = (TBXMLAttribute*)calloc(MAX_ATTRIBUTES,sizeof(TBXMLAttribute));
		currentAttribute = 0;
	}
	
	return &currentAttributeBuffer->attributes[currentAttribute];
}

@end
