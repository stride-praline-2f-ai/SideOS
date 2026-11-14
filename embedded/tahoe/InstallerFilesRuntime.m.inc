    if(isSideStore) {
        // lcMainBundle is LiveProcess.appex when the built-in installer runs
        // in a desktop window. The picker hooks are in the containing app,
        // not in the extension's nonexistent Frameworks directory.
        NSString *relativePickerHooks = isLiveProcess
            ? @"../../Frameworks/TweakLoader.dylib"
            : @"Frameworks/TweakLoader.dylib";
        NSString *pickerHooksPath = [[lcMainBundle.bundlePath
            stringByAppendingPathComponent:relativePickerHooks] stringByStandardizingPath];
        tweakLoaderLoaded = true;
        dlerror();
        void *pickerHooks = dlopen(pickerHooksPath.fileSystemRepresentation, RTLD_LAZY|RTLD_GLOBAL);
        NSString *pickerStatus;
        if (pickerHooks) {
            // The upstream DocumentPicker constructor enables this identity
            // hook automatically for the built-in installer. Confirm its
            // implementation came from TweakLoader for useful device logs.
            Method setter = class_getInstanceMethod(NSClassFromString(@"DOCConfiguration"),
                                                    NSSelectorFromString(@"setHostIdentifier:"));
            Dl_info implementationImage = {0};
            BOOL identityHook = setter && dladdr((const void *)method_getImplementation(setter),
                                                &implementationImage) && implementationImage.dli_fname &&
                [[[NSString stringWithUTF8String:implementationImage.dli_fname] lastPathComponent]
                    isEqualToString:@"TweakLoader.dylib"];
            pickerStatus = identityHook ? @"LiveContainer picker identity fix active"
                : @"LiveContainer picker library loaded; identity hook not confirmed";
        } else {
            const char *pickerError = dlerror();
            pickerStatus = [NSString stringWithFormat:@"LiveContainer picker library failed: %s",
                            pickerError ?: "unknown loader error"];
        }
        setenv("SI_INSTALLER_FILES_RUNTIME", pickerStatus.UTF8String, 1);
        NSLog(@"SideInstaller Files runtime: %@", pickerStatus);
    }
