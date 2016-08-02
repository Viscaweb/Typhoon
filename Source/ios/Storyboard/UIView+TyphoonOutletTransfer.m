////////////////////////////////////////////////////////////////////////////////
//
//  TYPHOON FRAMEWORK
//  Copyright 2015, Typhoon Framework Contributors
//  All Rights Reserved.
//
//  NOTICE: The authors permit you to use, modify, and distribute this file
//  in accordance with the terms of the license agreement accompanying it.
//
////////////////////////////////////////////////////////////////////////////////

#import "UIView+TyphoonOutletTransfer.h"
#import "NSLayoutConstraint+TyphoonOutletTransfer.h"
#import <objc/runtime.h>

@implementation UIView (TyphoonOutletTransfer)

- (void)setTyphoonNeedTransferOutlets:(BOOL)typhoonNeedTransferOutlets {
    objc_setAssociatedObject(self, @selector(typhoonNeedTransferOutlets), @(typhoonNeedTransferOutlets), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (BOOL)typhoonNeedTransferOutlets {
    return [objc_getAssociatedObject(self, @selector(typhoonNeedTransferOutlets)) boolValue];
}


// Swizzle didMoveToWindow
+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class class = [self class];
        
        SEL originalSelector = @selector(didMoveToWindow);
        SEL swizzledSelector = @selector(typhoon_didMoveToWindow);
        
        Method originalMethod = class_getInstanceMethod(class, originalSelector);
        Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector);
        
        BOOL didAddMethod = class_addMethod(class, originalSelector, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod));
        
        if (didAddMethod) {
            class_replaceMethod(class, swizzledSelector, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod));
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod);
        }
    });
}

- (void)typhoon_didMoveToWindow {
    [self typhoon_didMoveToWindow];
    // When view have superview transfer outlets if needed
    if (self.typhoonNeedTransferOutlets) {
        // recursive search of root view (superview without superview)
        UIView *rootView = [self findRootView:self];
        // recursive check and change outlets properties
        [self transferOutlets:rootView
                 transferView:self];
        // Mark that the transportation of finished
        self.typhoonNeedTransferOutlets = NO;
    }    
}

- (void)transferOutlets:(UIView *)view
           transferView:(UIView *)transferView {
    
    [self transferFromView:transferView];
    
    for (UIView *subview in view.subviews) {
        [subview transferOutlets:subview
                    transferView:transferView];
    }
}

- (void)transferFromView:(UIView *)view {
    
    unsigned count;
    objc_property_t *properties = class_copyPropertyList([self class], &count);
    
    unsigned i;
    for (i = 0; i < count; i++) {
        
        objc_property_t property = properties[i];
        const char *propName = property_getName(property);
        
        if(propName) {
            
            const char *propType = getPropertyType(property);
            NSString *propertyName = [NSString stringWithCString:propName
                                                        encoding:[NSString defaultCStringEncoding]];
            NSString *propertyType = [NSString stringWithCString:propType
                                                        encoding:[NSString defaultCStringEncoding]];
            // IBOutlet
            if (NSClassFromString(propertyType) == [NSLayoutConstraint class]) {
                [self transferConstraintOutletForKey:propertyName
                                           fromView:view];
            }
            // IBOutlet​Collection
            if ([NSClassFromString(propertyType) isSubclassOfClass:[NSArray class]]) {
                [self transferConstraintOutletsForKey:propertyName
                                             fromView:view];
            }
            
        }
        
    }
    
    free(properties);
}

- (void)transferConstraintOutletForKey:(NSString *)propertyName
                             fromView:(UIView *)view {
    NSLayoutConstraint *constraint = [self valueForKey:propertyName];
    if (constraint.typhoonTransferIdentifier) {
        for (NSLayoutConstraint *transferConstraint in view.constraints) {
            BOOL equalObjects = constraint == transferConstraint;
            BOOL equalIdentifier = [constraint.typhoonTransferIdentifier isEqualToString:transferConstraint.typhoonTransferIdentifier];
            if (!equalObjects && equalIdentifier) {
                [self setValue:transferConstraint
                        forKey:propertyName];
            }
        }
    }
}

- (void)transferConstraintOutletsForKey:(NSString *)propertyName
                             fromView:(UIView *)view {
    
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"self isMemberOfClass: %@",
                              [NSLayoutConstraint class]];
    NSArray *constraints = [self valueForKey:propertyName];
    NSArray *filtered = [constraints filteredArrayUsingPredicate:predicate];
    
    if (filtered.count > 0) {
        
        BOOL needChange = NO;
        NSMutableArray *newOutlets = [NSMutableArray new];
        
        for (id outlet in constraints) {
            
            id changeOutlet = outlet;

            if ([outlet isMemberOfClass:[NSLayoutConstraint class]]) {
        
                NSLayoutConstraint *constraint = outlet;
                
                if (constraint.typhoonTransferIdentifier) {
                    
                    for (NSLayoutConstraint *transferConstraint in view.constraints) {
                        
                        BOOL equalObjects = constraint == transferConstraint;
                        BOOL equalIdentifier = [constraint.typhoonTransferIdentifier isEqualToString:transferConstraint.typhoonTransferIdentifier];
                        
                        if (!equalObjects && equalIdentifier) {
                            changeOutlet = transferConstraint;
                            needChange = YES;
                        }
                        
                    }
                    
                }
            }
            
            [newOutlets addObject:changeOutlet];
            
        }
        
        if (needChange) {
            [self setValue:newOutlets
                    forKey:propertyName];
        }
        
    }
}

static const char *getPropertyType(objc_property_t property) {
    const char *attributes = property_getAttributes(property);
    char buffer[1 + strlen(attributes)];
    strlcpy(buffer, attributes, sizeof(buffer));
    char *state = buffer, *attribute;
    while ((attribute = strsep(&state, ",")) != NULL) {
        if (attribute[0] == 'T') {
            if (strlen(attribute) <= 4) {
                break;
            }
            return (const char *)[[NSData dataWithBytes:(attribute + 3) length:strlen(attribute) - 4] bytes];
        }
    }
    return "@";
}

- (UIView *)findRootView:(UIView *)view {
    if (view.superview) {
        return [view.superview findRootView:view.superview];
    }
    return view;
}

@end
