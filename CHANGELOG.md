# Changelog

## 1.0.0 (2026-09-03)


### ⚠ BREAKING CHANGES

* Minimum Dart SDK bumped to >=3.5.0.

### Features

* add 'include-methods' config to 'missing-test-assertion' rule ([#1026](https://github.com/Akhrameev/dart-code-linter/issues/1026)) ([83432e7](https://github.com/Akhrameev/dart-code-linter/commit/83432e7e3461a9072e0409b545f339a079137995))
* add `allow-only-once` option to `no-magic-number` rule ([#1173](https://github.com/Akhrameev/dart-code-linter/issues/1173)) ([8676f24](https://github.com/Akhrameev/dart-code-linter/commit/8676f24392df7b97efbb111218e975b1b008b294))
* add allow-initialized option to avoid-late-keyword ([#1145](https://github.com/Akhrameev/dart-code-linter/issues/1145)) ([d58a3f1](https://github.com/Akhrameev/dart-code-linter/commit/d58a3f1afebe4827f8d24cba4c1a1c4ba129bc55))
* add allow-nullable config option for avoid-returning-widgets ([#1180](https://github.com/Akhrameev/dart-code-linter/issues/1180)) ([d19a1e4](https://github.com/Akhrameev/dart-code-linter/commit/d19a1e4f011a4fb2a1cdb0d96561c6244bd19c74))
* add autofix for newline-before-return with edge-case fixture coverage ([#227](https://github.com/Akhrameev/dart-code-linter/issues/227)) ([c196357](https://github.com/Akhrameev/dart-code-linter/commit/c1963570179863df5bfdc9ebe70aa3adfadf92f0))
* add avoid-cascade-after-if-null rule ([#1039](https://github.com/Akhrameev/dart-code-linter/issues/1039)) ([0aec13e](https://github.com/Akhrameev/dart-code-linter/commit/0aec13e2e1975e54defdde2c81e59df22bcd3046))
* add avoid-creating-vector-in-update ([#1166](https://github.com/Akhrameev/dart-code-linter/issues/1166)) ([588a34d](https://github.com/Akhrameev/dart-code-linter/commit/588a34d9e7f3a3ee40b35e158bb46ca84ccdee02))
* add avoid-double-slash-imports rule ([#1095](https://github.com/Akhrameev/dart-code-linter/issues/1095)) ([e77069d](https://github.com/Akhrameev/dart-code-linter/commit/e77069d3b7cf5bb542ec6fc4cb6ed926a61f77fa))
* add avoid-substring rule ([#1206](https://github.com/Akhrameev/dart-code-linter/issues/1206)) ([85be501](https://github.com/Akhrameev/dart-code-linter/commit/85be501cbcf55767852aaa124d5778ccd546ef1b))
* add avoid-unnecessary-conditionals rule ([#1094](https://github.com/Akhrameev/dart-code-linter/issues/1094)) ([7a96369](https://github.com/Akhrameev/dart-code-linter/commit/7a963694458cf7bcb1a10516095e9e6f197b1aff))
* add example ([bf1431b](https://github.com/Akhrameev/dart-code-linter/commit/bf1431b9b0a2bee5c3b31261fdb2c30b1ff6892e))
* add example ([8dc2e35](https://github.com/Akhrameev/dart-code-linter/commit/8dc2e353b5310bb34de00e391573b05ebe1ee220))
* add example ([b744fc9](https://github.com/Akhrameev/dart-code-linter/commit/b744fc9493f5001c5b1a853ac13a544b68c9070e))
* add ignored-types option to avoid-late-keyword ([#1146](https://github.com/Akhrameev/dart-code-linter/issues/1146)) ([00d83a6](https://github.com/Akhrameev/dart-code-linter/commit/00d83a63eb410a2890be70282a4e5d14f8089415))
* add list-all-equatable-fields rule ([#1103](https://github.com/Akhrameev/dart-code-linter/issues/1103)) ([8eae6f6](https://github.com/Akhrameev/dart-code-linter/commit/8eae6f61f0f4ac22ca37efb3486f88ea04661276))
* add logger and progress indication ([#1014](https://github.com/Akhrameev/dart-code-linter/issues/1014)) ([e209a2d](https://github.com/Akhrameev/dart-code-linter/commit/e209a2d7ba0b9d3c246348f24693b493cdd3230e))
* add method call chains support on ban-name ident ([#1034](https://github.com/Akhrameev/dart-code-linter/issues/1034)) ([3b48b76](https://github.com/Akhrameev/dart-code-linter/commit/3b48b76f385ef37aacd9aaea1fa599c1d4da657a))
* add new config option ([#1187](https://github.com/Akhrameev/dart-code-linter/issues/1187)) ([8430b4a](https://github.com/Akhrameev/dart-code-linter/commit/8430b4adc742b1093fd21e1d8bde6dbc13802ffa))
* add new rule correct-game-instantiating ([#1163](https://github.com/Akhrameev/dart-code-linter/issues/1163)) ([c3a124a](https://github.com/Akhrameev/dart-code-linter/commit/c3a124a5a3c461a0b3cffd981c047121f28d91f1))
* add new rule prefer-media-query-direct-access ([7d257c5](https://github.com/Akhrameev/dart-code-linter/commit/7d257c5181ec5a210df194556f3c990e750d4e2e))
* add new rule prefer-media-query-direct-access ([546f86b](https://github.com/Akhrameev/dart-code-linter/commit/546f86be573dff31dc6b5760c5a4a5e2b1da472f))
* Add new rules ([#260](https://github.com/Akhrameev/dart-code-linter/issues/260)) ([12642bc](https://github.com/Akhrameev/dart-code-linter/commit/12642bccdce342d7fe761e08fa2a4f664a6c5501))
* add prefer-define-hero-tag rule ([#1184](https://github.com/Akhrameev/dart-code-linter/issues/1184)) ([1709f2d](https://github.com/Akhrameev/dart-code-linter/commit/1709f2dd4db5239bf31f03f018fd6b2ce6d15d59))
* add presets ([9a1efe4](https://github.com/Akhrameev/dart-code-linter/commit/9a1efe4fa8dcb127a4983aac43f01dc7ba337a42))
* add pressets ([95b1d0e](https://github.com/Akhrameev/dart-code-linter/commit/95b1d0e8375e00d74c4a2b678fe58bf95639bebc))
* add print-config option to analyze command ([#1057](https://github.com/Akhrameev/dart-code-linter/issues/1057)) ([d8dbead](https://github.com/Akhrameev/dart-code-linter/commit/d8dbead9ecfd8452a03b32c6c6f2a0406440218b))
* add rule prefer-named-record-fields ([50b2177](https://github.com/Akhrameev/dart-code-linter/commit/50b2177744243db13de3d8534b0d1b405a193920))
* add rule prefer-named-record-fields ([bd24366](https://github.com/Akhrameev/dart-code-linter/commit/bd24366647caf8d28ee5f59a0876b5a9a0fdcfed))
* add static code diagnostic `prefer-using-list-view` ([#1088](https://github.com/Akhrameev/dart-code-linter/issues/1088)) ([8039dba](https://github.com/Akhrameev/dart-code-linter/commit/8039dbaed886f1abd4afd16602c39c523806cb0e))
* add static code diagnostic arguments-ordering ([#1047](https://github.com/Akhrameev/dart-code-linter/issues/1047)) ([dea2cc0](https://github.com/Akhrameev/dart-code-linter/commit/dea2cc06b42bf4b5eda3830789f16f973d9f17f5))
* add static code diagnostic avoid-initializing-in-on-mount ([#1165](https://github.com/Akhrameev/dart-code-linter/issues/1165)) ([ad87db1](https://github.com/Akhrameev/dart-code-linter/commit/ad87db1491a62710f5589fcc72dec190fc1260ee))
* add static code diagnostic avoid-redundant-async ([#1002](https://github.com/Akhrameev/dart-code-linter/issues/1002)) ([3dd127e](https://github.com/Akhrameev/dart-code-linter/commit/3dd127e5bf02bdc7f95bedae8520baa454852c28))
* add static code diagnostic avoid-redundant-async-on-load ([#1168](https://github.com/Akhrameev/dart-code-linter/issues/1168)) ([755ca4f](https://github.com/Akhrameev/dart-code-linter/commit/755ca4fbdca9b379c34604ff7bcb769b10f0a2dd))
* add static code diagnostic check-for-equals-in-render-object-setters ([#1003](https://github.com/Akhrameev/dart-code-linter/issues/1003)) ([e773d30](https://github.com/Akhrameev/dart-code-linter/commit/e773d30508832d9e921f03ef2dfd98816429af00))
* add static code diagnostic consistent-update-render-object ([#1004](https://github.com/Akhrameev/dart-code-linter/issues/1004)) ([b235f78](https://github.com/Akhrameev/dart-code-linter/commit/b235f787a1b3bb1f84377c0f43fdea24ab8399ee))
* add static code diagnostic missing-test-assertion ([#1023](https://github.com/Akhrameev/dart-code-linter/issues/1023)) ([7db4f86](https://github.com/Akhrameev/dart-code-linter/commit/7db4f860315a0be808a4d9d2d512755600a12c96))
* add static code diagnostic prefer-correct-test-file-name ([#1000](https://github.com/Akhrameev/dart-code-linter/issues/1000)) ([1d8e535](https://github.com/Akhrameev/dart-code-linter/commit/1d8e5355cfe9350b7b6b34fe4276a736a67a1896))
* add static code diagnostic prefer-iterable-of ([#999](https://github.com/Akhrameev/dart-code-linter/issues/999)) ([a254d6e](https://github.com/Akhrameev/dart-code-linter/commit/a254d6e34503482e9955723fb7dec17d132ca06c))
* add static code diagnostic prefer-static-class ([#1086](https://github.com/Akhrameev/dart-code-linter/issues/1086)) ([4900412](https://github.com/Akhrameev/dart-code-linter/commit/4900412d56d24e649ae9dc1bbefb249a831c28bb))
* add strict config option to avoid-collection-methods-with-unrelated-types ([#1111](https://github.com/Akhrameev/dart-code-linter/issues/1111)) ([2dd4c83](https://github.com/Akhrameev/dart-code-linter/commit/2dd4c83a2f20a2b97e3369ce8e76494c59589373))
* add support for presets ([#1025](https://github.com/Akhrameev/dart-code-linter/issues/1025)) ([5408c36](https://github.com/Akhrameev/dart-code-linter/commit/5408c36bd03d61ba715473b5df913bb5b772c81e))
* add usage analytics ([f09d04d](https://github.com/Akhrameev/dart-code-linter/commit/f09d04d537608fdbbf4707ac817e8d3e3a0ad274))
* add use-setstate-synchronously rule ([#1120](https://github.com/Akhrameev/dart-code-linter/issues/1120)) ([ea9eaad](https://github.com/Akhrameev/dart-code-linter/commit/ea9eaad23ddbbd3621184dca728a15274f7900f6))
* add validation for rule names in analysis_options ([#1059](https://github.com/Akhrameev/dart-code-linter/issues/1059)) ([b12807d](https://github.com/Akhrameev/dart-code-linter/commit/b12807d2e01c37f80d598cf998b02355d5e35d94))
* analyzer 13.x support (release 4.1.0) ([#237](https://github.com/Akhrameev/dart-code-linter/issues/237)) ([2b9f6d7](https://github.com/Akhrameev/dart-code-linter/commit/2b9f6d73413cded2186b6c84bd16b29769ac961a))
* append new presset `analysis_options.1.0.0.yaml` ([#120](https://github.com/Akhrameev/dart-code-linter/issues/120)) ([5679d0e](https://github.com/Akhrameev/dart-code-linter/commit/5679d0efb47009865fd9bcbbaca8c5c193483e37))
* avoid passing async when sync expected ([#987](https://github.com/Akhrameev/dart-code-linter/issues/987)) ([d0b230a](https://github.com/Akhrameev/dart-code-linter/commit/d0b230aac614c9d8b2e5a3ce34588ccb2249e316))
* **avoid-duplicate-exports:** add auto-fix to delete the duplicate export directive ([#247](https://github.com/Akhrameev/dart-code-linter/issues/247)) ([63dba63](https://github.com/Akhrameev/dart-code-linter/commit/63dba638f14a2d71164b09c5239f5b34b12d921d))
* **avoid-unnecessary-type-casts:** add auto-fix to remove redundant cast ([#244](https://github.com/Akhrameev/dart-code-linter/issues/244)) ([2d631ac](https://github.com/Akhrameev/dart-code-linter/commit/2d631ac48a4f97d7f786b13453c4c09f4f6cad62))
* change element2 to element ([2e4ed13](https://github.com/Akhrameev/dart-code-linter/commit/2e4ed134ce50ed65cf6f5b45d5eb4ce509290373))
* change severity for avoid-banned-imports, prefer-trailing-comma, ban-name rules ([#1052](https://github.com/Akhrameev/dart-code-linter/issues/1052)) ([6f4985d](https://github.com/Akhrameev/dart-code-linter/commit/6f4985d4e900ee355901117bf1098bae91042d64))
* cleanup public API ([#1053](https://github.com/Akhrameev/dart-code-linter/issues/1053)) ([5ef6fba](https://github.com/Akhrameev/dart-code-linter/commit/5ef6fba77d4d8ac248932d3455a723819b444588))
* exclude `.freezed.dart` files by default ([#1139](https://github.com/Akhrameev/dart-code-linter/issues/1139)) ([592cd3d](https://github.com/Akhrameev/dart-code-linter/commit/592cd3def96cfba664fec36c8d8d347b0a35c150))
* export cli runner and add documentation for use-case ([#1040](https://github.com/Akhrameev/dart-code-linter/issues/1040)) ([267cc4f](https://github.com/Akhrameev/dart-code-linter/commit/267cc4fd1a98d3b7bd7f0c35bba8863bb9e19cf4))
* handle widget members order separately ([#1043](https://github.com/Akhrameev/dart-code-linter/issues/1043)) ([371f598](https://github.com/Akhrameev/dart-code-linter/commit/371f598e5f170f0b25255ea28161050ba548c7c8))
* ignore tear-off methods for avoid-unused-parameters ([#1126](https://github.com/Akhrameev/dart-code-linter/issues/1126)) ([050f133](https://github.com/Akhrameev/dart-code-linter/commit/050f133d1729dc5b297d99ea359e9fbb93680e1c))
* improve readme ([396c5ea](https://github.com/Akhrameev/dart-code-linter/commit/396c5ea01d1e60b3238fdd704677d5cc07892812))
* improve readme and add global pubspec file ([805eb6a](https://github.com/Akhrameev/dart-code-linter/commit/805eb6aa543ba5595b43fddd656aa6aca5d4c238))
* improve readme and add global pubspec file ([24ce2a6](https://github.com/Akhrameev/dart-code-linter/commit/24ce2a66f16e785fd991844147c7a20bb066202f))
* improve readme and add global pubspec file ([a4167e4](https://github.com/Akhrameev/dart-code-linter/commit/a4167e478af7bc967d16c5c98a5765a45245064f))
* increase version ([872e3a3](https://github.com/Akhrameev/dart-code-linter/commit/872e3a3127fdeaaf34a5447f916e33000470a85b))
* increase version ([aab59e2](https://github.com/Akhrameev/dart-code-linter/commit/aab59e284f8340e2cda634d9acdc72f33239f9dc))
* increase version ([c2a234c](https://github.com/Akhrameev/dart-code-linter/commit/c2a234ceccdbf81e1e337f385359989dc2eadb85))
* increase version 1.1.5 ([6959c25](https://github.com/Akhrameev/dart-code-linter/commit/6959c25320d0663164e6337db35ab7b7d3cb81aa))
* increase version 1.1.5 ([62686bc](https://github.com/Akhrameev/dart-code-linter/commit/62686bca168e320810d3f67cb1bc7e5fe5f331cb))
* introduce prefer-provide-intl-description rule ([#1137](https://github.com/Akhrameev/dart-code-linter/issues/1137)) ([29e6181](https://github.com/Akhrameev/dart-code-linter/commit/29e6181c58e0040d9a96eff61b2274fb430bafe6))
* make avoid-unnecessary-type-assertions handle is! checks ([#995](https://github.com/Akhrameev/dart-code-linter/issues/995)) ([489eb25](https://github.com/Akhrameev/dart-code-linter/commit/489eb259d8ec77d6d4b9baca676d8030c4e23a3a))
* migrate to new plugins api ([#1020](https://github.com/Akhrameev/dart-code-linter/issues/1020)) ([ec223c7](https://github.com/Akhrameev/dart-code-linter/commit/ec223c71d2b675cc48c787992bd595a725bdba0c))
* **new_rules_and_multiple_suggestions:** adapt barrel rule message ([264d52e](https://github.com/Akhrameev/dart-code-linter/commit/264d52e21eea007dbcd8e4c6d1ac7e269d68de70))
* **new_rules_and_multiple_suggestions:** add rules to rules factory ([cbed444](https://github.com/Akhrameev/dart-code-linter/commit/cbed444c1fe5aeec20c6ea71456b20c9de094a10))
* **new_rules_and_multiple_suggestions:** add some docs ([622d8bd](https://github.com/Akhrameev/dart-code-linter/commit/622d8bd08aa32af5990e44a99152825ff67c9d95))
* **new_rules_and_multiple_suggestions:** add use_design_system_item and only_barrel_import rules and adapt codebase to multiple suggestions ([b89a821](https://github.com/Akhrameev/dart-code-linter/commit/b89a8213dd0d6fb0e5d7f514e7731fbff4a4b188))
* **new_rules_and_multiple_suggestions:** bump version ([6e89367](https://github.com/Akhrameev/dart-code-linter/commit/6e89367ea72fdf7b598cfb45b705e2a0e56fa129))
* **new_rules_and_multiple_suggestions:** fix conflicts ([afacbe3](https://github.com/Akhrameev/dart-code-linter/commit/afacbe3dd7914a1998235de8af86af783630f2e5))
* **new_rules_and_multiple_suggestions:** fix conflicts ([90d4cd2](https://github.com/Akhrameev/dart-code-linter/commit/90d4cd2401501252594c67b16c93653221f8cde8))
* **new_rules_and_multiple_suggestions:** fix pr issues ([e4f7937](https://github.com/Akhrameev/dart-code-linter/commit/e4f79371a7f8718d96392aba83acb40bc422bd80))
* **new_rules_and_multiple_suggestions:** fix priority & bump version ([ce51d1a](https://github.com/Akhrameev/dart-code-linter/commit/ce51d1a4005fcd8f38592d270f81baea63b482c4))
* **new_rules_and_multiple_suggestions:** fix tests ([3bf41df](https://github.com/Akhrameev/dart-code-linter/commit/3bf41df878a568dae20c2130f0fde47aea5bb3fb))
* **new_rules_and_multiple_suggestions:** remove todo ([54c69c1](https://github.com/Akhrameev/dart-code-linter/commit/54c69c158052107b9a1bf387cc89a8398ff6f1b3))
* **no-blank-line-before-single-return:** add auto-fix and fix trailing-brace false positive ([#245](https://github.com/Akhrameev/dart-code-linter/issues/245)) ([432bb45](https://github.com/Akhrameev/dart-code-linter/commit/432bb4552b19f5fd394dd3898f0cb66c3c7b4936))
* **prefer-enums-by-name:** add guarded auto-fix to convert firstWhere to values.byName (4.1.6) ([#248](https://github.com/Akhrameev/dart-code-linter/issues/248)) ([d50c899](https://github.com/Akhrameev/dart-code-linter/commit/d50c8995e244bda72ccb7f991de2a2566e4b12b2))
* **prefer-match-file-name:** add config for excluding enums and typedefs ([#242](https://github.com/Akhrameev/dart-code-linter/issues/242)) ([ebcab9b](https://github.com/Akhrameev/dart-code-linter/commit/ebcab9b2b16bb190403ffacdfb1cab2efa967572))
* **prefer-moving-to-variable:** add ignored-invocations and ignored-targets options ([#218](https://github.com/Akhrameev/dart-code-linter/issues/218)) ([17f3cb5](https://github.com/Akhrameev/dart-code-linter/commit/17f3cb557eb3d12933f9146f63e73c0616910c81))
* publish pipeline ([58a7935](https://github.com/Akhrameev/dart-code-linter/commit/58a7935cbb6bd3b2a4a6b13ae60a4279240a759f))
* remove angular rules ([744d607](https://github.com/Akhrameev/dart-code-linter/commit/744d607ddc9820a122635110711ada4163414329))
* remove angular rules ([02fe3c5](https://github.com/Akhrameev/dart-code-linter/commit/02fe3c531899472566920db654257a0f1c5f351a))
* remove angular rules ([979042f](https://github.com/Akhrameev/dart-code-linter/commit/979042f2b36de9d129815a24e727994e2a94f1d0))
* rename common rules to dart rules ([cb25cf4](https://github.com/Akhrameev/dart-code-linter/commit/cb25cf4b9edde1b720ccd8c2650afb9030324f5c))
* rename common rules to dart rules ([880ef74](https://github.com/Akhrameev/dart-code-linter/commit/880ef74683bd3bc4e59f9cbfdf2463f12e3cf955))
* rename member-ordering-extended to member-ordering ([#1041](https://github.com/Akhrameev/dart-code-linter/issues/1041)) ([c515313](https://github.com/Akhrameev/dart-code-linter/commit/c5153133e5dc4e20816d7cda724e5f0a58be5ca4))
* show warning for rules without config that require config to work ([#1125](https://github.com/Akhrameev/dart-code-linter/issues/1125)) ([2bb60d4](https://github.com/Akhrameev/dart-code-linter/commit/2bb60d488d5213e6e6ec03349d62daedeee9f0f0))
* support boolean literals removal for prefer-conditional-expressions auto-fix ([#1096](https://github.com/Akhrameev/dart-code-linter/issues/1096)) ([9b1efee](https://github.com/Akhrameev/dart-code-linter/commit/9b1efee99b9b6fd29ad20efb592c8ecf0e3ecf69))
* support context.mounted for use-setstate-synchronously ([#1164](https://github.com/Akhrameev/dart-code-linter/issues/1164)) ([d20764e](https://github.com/Akhrameev/dart-code-linter/commit/d20764e6cf7b30ed4fac9b939510ba37f17d1dd0))
* support dynamic method name for member-ordering ([#1044](https://github.com/Akhrameev/dart-code-linter/issues/1044)) ([1b6a848](https://github.com/Akhrameev/dart-code-linter/commit/1b6a848e2413d6b9e3eb80a93f8dab5f695cee15))
* support ignoring nesting for prefer-conditional-expressions ([#1122](https://github.com/Akhrameev/dart-code-linter/issues/1122)) ([8feb0e9](https://github.com/Akhrameev/dart-code-linter/commit/8feb0e90f25282bdec3e53c8aea6f1ae25a9b5cd))
* support ignoring regular comments for format-comment ([#1110](https://github.com/Akhrameev/dart-code-linter/issues/1110)) ([8ec23cb](https://github.com/Akhrameev/dart-code-linter/commit/8ec23cb76a7c5d74f38af5a7bdaf71bb35aeed05))
* support includes in the rules config ([#1061](https://github.com/Akhrameev/dart-code-linter/issues/1061)) ([9d28572](https://github.com/Akhrameev/dart-code-linter/commit/9d28572970f432835c177a658dbfc142bf3d4ac6))
* support proxy calls for check-unused-l10n ([#1054](https://github.com/Akhrameev/dart-code-linter/issues/1054)) ([f1bca85](https://github.com/Akhrameev/dart-code-linter/commit/f1bca8572e3a131c2da5068307eaf7a253cd0a6a))
* support report to the json file option for the analyze command ([#1042](https://github.com/Akhrameev/dart-code-linter/issues/1042)) ([64f8d3f](https://github.com/Akhrameev/dart-code-linter/commit/64f8d3f2396d74aba147a3be83b7b7c32edc9d5c))
* support type=lint suppression ([#1156](https://github.com/Akhrameev/dart-code-linter/issues/1156)) ([ab95f02](https://github.com/Akhrameev/dart-code-linter/commit/ab95f0227229c06cd493ce42886893d4fa1cc710))
* threshold options ([9ca1ca0](https://github.com/Akhrameev/dart-code-linter/commit/9ca1ca05ce1a80122988e17e305c2b33b58b780c))
* threshold options ([e55205b](https://github.com/Akhrameev/dart-code-linter/commit/e55205b7d82a3ddada824d1f71c521a10a272231))
* **unused-code:** detect unused private class members behind a flag ([#176](https://github.com/Akhrameev/dart-code-linter/issues/176)) ([#259](https://github.com/Akhrameev/dart-code-linter/issues/259)) ([be95d7c](https://github.com/Akhrameev/dart-code-linter/commit/be95d7c324ae127e8bc37667c07a8f0a7e235e47))
* **unused-code:** detect unused public members behind a flag ([#176](https://github.com/Akhrameev/dart-code-linter/issues/176)) ([#268](https://github.com/Akhrameev/dart-code-linter/issues/268)) ([ee53c11](https://github.com/Akhrameev/dart-code-linter/commit/ee53c1137a824bcdda73258885e74307ef66687e))
* update analyzer dependency ([d66a8e1](https://github.com/Akhrameev/dart-code-linter/commit/d66a8e14e2373af6ab9a208888c4c1892c6e847f))
* Update pubspec.yaml ([e82df32](https://github.com/Akhrameev/dart-code-linter/commit/e82df32695dcb78086303a2932901fd7bb382f81))
* upgrade analyzer ([e29cfc0](https://github.com/Akhrameev/dart-code-linter/commit/e29cfc07e2459314a7c9652ce8890f12bd68fc6f))
* upgrade analyzer ([d3d71a0](https://github.com/Akhrameev/dart-code-linter/commit/d3d71a0a1299d1ff203098ff9436c0b6efd9476f))
* upgrade analyzer 6.x ([9766654](https://github.com/Akhrameev/dart-code-linter/commit/976665473056877f5bb2bf088542a6d5258e90ee))


### Bug Fixes

* add const to edge insets constructors when appropriate ([#972](https://github.com/Akhrameev/dart-code-linter/issues/972)) ([d041809](https://github.com/Akhrameev/dart-code-linter/commit/d041809fe6051fad268e6e865f753347770368df))
* add fail assertion as a valid method to missing_test_assertion rule ([#1069](https://github.com/Akhrameev/dart-code-linter/issues/1069)) ([c16dded](https://github.com/Akhrameev/dart-code-linter/commit/c16ddedbdc6019fd90fe6d23f4e9ffbffee7afda))
* Add rule 'missing-test-assertion' in rules factory ([#1024](https://github.com/Akhrameev/dart-code-linter/issues/1024)) ([c573273](https://github.com/Akhrameev/dart-code-linter/commit/c573273cd46fa33a1350946f200dee25c80097a4))
* add threshold options ([5405d0c](https://github.com/Akhrameev/dart-code-linter/commit/5405d0cbb7f9e9a9f61cc7c35d853de553a9a495))
* add unnecessary nullable exports ([df886a8](https://github.com/Akhrameev/dart-code-linter/commit/df886a8c1677e2398aff7f411a2dc6df7f6da48e))
* additional cases for `use-setstate-synchronously` ([#1136](https://github.com/Akhrameev/dart-code-linter/issues/1136)) ([fa61a59](https://github.com/Akhrameev/dart-code-linter/commit/fa61a59225b31a910101442e7a8ab0ce7270247c))
* address PR [#216](https://github.com/Akhrameev/dart-code-linter/issues/216) review feedback and resolve merge conflicts ([#221](https://github.com/Akhrameev/dart-code-linter/issues/221)) ([089aa87](https://github.com/Akhrameev/dart-code-linter/commit/089aa87741ed8795558eb1eef9a0d4cde1502643))
* **analyzer-plugin:** replace deprecated getChildAssumingFile with getFile ([#250](https://github.com/Akhrameev/dart-code-linter/issues/250)) ([#254](https://github.com/Akhrameev/dart-code-linter/issues/254)) ([814cc27](https://github.com/Akhrameev/dart-code-linter/commit/814cc2726040c17a4cd0e79e3c82f2cd04addbb2))
* apply format ([41bba7f](https://github.com/Akhrameev/dart-code-linter/commit/41bba7ff275b5597f1cee326a752874b7af7cfb1))
* avoid dynamic to extensions ([6de4f9d](https://github.com/Akhrameev/dart-code-linter/commit/6de4f9d3c9ac2c2f4789d115e1859a64673fc421))
* avoid dynamic to extensions ([66623cf](https://github.com/Akhrameev/dart-code-linter/commit/66623cf25c782cadbe3c52c10c336f4e33ec39d7))
* avoid null check exception in the analyzer ([#1099](https://github.com/Akhrameev/dart-code-linter/issues/1099)) ([8b2b4f3](https://github.com/Akhrameev/dart-code-linter/commit/8b2b4f3be7f394a1263658a7f76f0ebdc3ede72f))
* **avoid-passing-async-when-sync-expected:** FutureOr Functions are interpreted as synchronous functions ([#1036](https://github.com/Akhrameev/dart-code-linter/issues/1036)) ([1ab388a](https://github.com/Akhrameev/dart-code-linter/commit/1ab388a8646dc1af3c488833c78df8efab0def10))
* **avoid-unused-parameters:** replace deprecated MethodDeclaration.isAbstract across analyzer matrix ([#253](https://github.com/Akhrameev/dart-code-linter/issues/253)) ([d2c1e9d](https://github.com/Akhrameev/dart-code-linter/commit/d2c1e9dfe1167018c4736122e676403b7c2f0ec3))
* change rule category ([c56f5dd](https://github.com/Akhrameev/dart-code-linter/commit/c56f5dd901a8e5c8dc50882bee91f7699238ae08))
* change rule category ([04b199b](https://github.com/Akhrameev/dart-code-linter/commit/04b199b60c1e576bf9be384966590a0824fdebfc))
* check `of` constructor exist for `prefer-iterable-of` ([#1050](https://github.com/Akhrameev/dart-code-linter/issues/1050)) ([0f646c4](https://github.com/Akhrameev/dart-code-linter/commit/0f646c45e546f6a3189b0fe7cf82d37e717ce155))
* check didChangeDependencies for avoid-unnecessary-setstate ([#1188](https://github.com/Akhrameev/dart-code-linter/issues/1188)) ([e2f0dd2](https://github.com/Akhrameev/dart-code-linter/commit/e2f0dd25a9b08126efc4758a275738354bebd7db))
* correct packageVersion constant and bump to 4.0.2 ([#230](https://github.com/Akhrameev/dart-code-linter/issues/230)) ([b7de35f](https://github.com/Akhrameev/dart-code-linter/commit/b7de35fbc691b8325abc9c2bcf1f9726c14baac7))
* correctly available check rule names ([#1068](https://github.com/Akhrameev/dart-code-linter/issues/1068)) ([8bc1a3c](https://github.com/Akhrameev/dart-code-linter/commit/8bc1a3c228d09c394ebf69eee6ec810ceac3f650))
* correctly handle dynamic type for avoid-passing-async-when-sync-expected ([#1189](https://github.com/Akhrameev/dart-code-linter/issues/1189)) ([0c0243d](https://github.com/Akhrameev/dart-code-linter/commit/0c0243da1ebe944533cfe82df3374f952e3bf94c))
* correctly handle empty comment sentence for format-comment ([#1159](https://github.com/Akhrameev/dart-code-linter/issues/1159)) ([7a40cb3](https://github.com/Akhrameev/dart-code-linter/commit/7a40cb35bbcf93b1440d948abddf807f0d90552b))
* correctly handle FunctionExpressions for avoid-redundant-async ([#1124](https://github.com/Akhrameev/dart-code-linter/issues/1124)) ([8af25bd](https://github.com/Akhrameev/dart-code-linter/commit/8af25bdf86fa47dad7b9ca92c6d28d58ecf474c5))
* correctly handle implicit type parameters for no-equal-arguments ([#1190](https://github.com/Akhrameev/dart-code-linter/issues/1190)) ([b822357](https://github.com/Akhrameev/dart-code-linter/commit/b8223572feb45984ab92e597615d7582a020e9c3))
* correctly handle prefixed enums and static instance fields for prefer-moving-to-variable ([#1123](https://github.com/Akhrameev/dart-code-linter/issues/1123)) ([b4d5cbc](https://github.com/Akhrameev/dart-code-linter/commit/b4d5cbc1eaecf34303e2f8cb5004bc58bd3e633a))
* correctly support conditional imports for check-unused-code ([#1097](https://github.com/Akhrameev/dart-code-linter/issues/1097)) ([f395fd5](https://github.com/Akhrameev/dart-code-linter/commit/f395fd5cd6b9baa3d61208491fca99a999cb2ee8))
* correctly support dartdoc tags for format-comment ([#1182](https://github.com/Akhrameev/dart-code-linter/issues/1182)) ([d1d7dd8](https://github.com/Akhrameev/dart-code-linter/commit/d1d7dd841a91a3626ac522d4f222873eb928b6b9))
* correctly track prefixes usage for check-unused-code ([#1208](https://github.com/Akhrameev/dart-code-linter/issues/1208)) ([6074aef](https://github.com/Akhrameev/dart-code-linter/commit/6074aef57836d433d791bf3a457e67a4fb7acec1))
* dart analysis ([9f904c6](https://github.com/Akhrameev/dart-code-linter/commit/9f904c6937bdc3367b9f26aedeb3b736dff8ad9f))
* dart analysis ([57dc3bb](https://github.com/Akhrameev/dart-code-linter/commit/57dc3bb938a8a14b6631275ba7f448c4259ad73c))
* delete dev_dependencies ([e21ed2f](https://github.com/Akhrameev/dart-code-linter/commit/e21ed2fecc647103c73d579eccdd669223ad713b))
* example ([f2b703a](https://github.com/Akhrameev/dart-code-linter/commit/f2b703ade41faa0704a109aa98b36dac60980a43))
* example ([ce906fe](https://github.com/Akhrameev/dart-code-linter/commit/ce906fe7adcccae38ddc0a9b352994fffd02a23b))
* example ([a3c8f73](https://github.com/Akhrameev/dart-code-linter/commit/a3c8f7311fdf3024a652fffe412973ed117065e2))
* example ([e21605c](https://github.com/Akhrameev/dart-code-linter/commit/e21605c8ee0169ec2649d0c312117facfad42413))
* example ([aefb389](https://github.com/Akhrameev/dart-code-linter/commit/aefb38938c5728291d855aaa1f55cb1878754e6c))
* example ([806e43d](https://github.com/Akhrameev/dart-code-linter/commit/806e43da39e2f616a592714908946912811c7273))
* example ([2152319](https://github.com/Akhrameev/dart-code-linter/commit/2152319ba97529f002cabcab39b958619657b870))
* example ([2cfe424](https://github.com/Akhrameev/dart-code-linter/commit/2cfe42498dc74103caa6742d3e8840786ab728ba))
* export missing parts of public API ([#1161](https://github.com/Akhrameev/dart-code-linter/issues/1161)) ([ae2674f](https://github.com/Akhrameev/dart-code-linter/commit/ae2674feb1c9a1f72481f4cad8d367110a7e58a7))
* Fix changelog URL for update available warning. ([39bb81f](https://github.com/Akhrameev/dart-code-linter/commit/39bb81f0c07f8ca6b000d1dafdd8e876a65bebf0))
* Fix changelog URL for update available warning. ([48299b9](https://github.com/Akhrameev/dart-code-linter/commit/48299b9a76b20a3444d480a7ebf1f8b57ea4126f))
* fix DCL version in analyzer_plugin ([ca37d4a](https://github.com/Akhrameev/dart-code-linter/commit/ca37d4a4d30e7e165ebe385b83b61bb31fee17c7))
* fix excludes for rules intended only for tests ([#1022](https://github.com/Akhrameev/dart-code-linter/issues/1022)) ([e60e9f9](https://github.com/Akhrameev/dart-code-linter/commit/e60e9f90b11907ef3895e52ceb19607e5da6ef8c))
* fix moving to variable false positives ([#1186](https://github.com/Akhrameev/dart-code-linter/issues/1186)) ([af1cc2e](https://github.com/Akhrameev/dart-code-linter/commit/af1cc2e0f5b86ec0f3412ef844e6b097e486dd17))
* fix regression in avoid-unnecessary-type-assertions ([ad3b9fe](https://github.com/Akhrameev/dart-code-linter/commit/ad3b9fe73f7bc80960306f33c6361a1908bbd321))
* fix regression in is! checks for avoid-unnecessary-type-assertions ([24f3636](https://github.com/Akhrameev/dart-code-linter/commit/24f3636bcfda8eb25f1537bf792bea6ec1be1a95))
* generating report file when find issues in the report ([a5abc1a](https://github.com/Akhrameev/dart-code-linter/commit/a5abc1a6dff3fb139e1478e268dabf6375de5a03))
* generating report file when find issues in the report ([0c08eee](https://github.com/Akhrameev/dart-code-linter/commit/0c08eee1e99e9426283d13aab3ed1321cb73e54a))
* handle dynamics in map literals for avoid-dynamic ([87add35](https://github.com/Akhrameev/dart-code-linter/commit/87add359fb62ccbbc844dbde8c28b65c9c2f4fd1))
* handle dynamics in map literals for avoid-dynamic ([#1194](https://github.com/Akhrameev/dart-code-linter/issues/1194)) ([1edfd17](https://github.com/Akhrameev/dart-code-linter/commit/1edfd17d53d6a75364a8beb3fbd741d652ba77b4))
* handle multiline comments ([#1129](https://github.com/Akhrameev/dart-code-linter/issues/1129)) ([c752d23](https://github.com/Akhrameev/dart-code-linter/commit/c752d2375baa7f0bfddfebf9cf67f468e555a3e7))
* handle property access for unnecessary nullable tear-offs ([1bffe50](https://github.com/Akhrameev/dart-code-linter/commit/1bffe507248311fdbb48cdce753a03d004417b55))
* ignore doc comments for prefer-commenting-analyzer-ignores ([#1115](https://github.com/Akhrameev/dart-code-linter/issues/1115)) ([07d139f](https://github.com/Akhrameev/dart-code-linter/commit/07d139fa2d7369d47e8e7960813dd37dd26d1d6d))
* ignore enum constant arguments for no-magic-number ([#1150](https://github.com/Akhrameev/dart-code-linter/issues/1150)) ([7f9e642](https://github.com/Akhrameev/dart-code-linter/commit/7f9e6425e69ae20ef9d1c12512cea506192027ee))
* ignore method invocations in a variable declaration for prefer-moving-to-variable ([#1144](https://github.com/Akhrameev/dart-code-linter/issues/1144)) ([dbdc63e](https://github.com/Akhrameev/dart-code-linter/commit/dbdc63e728193b6ed508305c46e94ac0add048fc))
* ignore override methods for avoid-redundant-async ([#1060](https://github.com/Akhrameev/dart-code-linter/issues/1060)) ([9214579](https://github.com/Akhrameev/dart-code-linter/commit/92145791961fc21a0c59455ee3cd435a25404a12))
* ignore Providers for avoid-returning-widgets ([#1121](https://github.com/Akhrameev/dart-code-linter/issues/1121)) ([2e0c6da](https://github.com/Akhrameev/dart-code-linter/commit/2e0c6dac457d097b64fbcd416a0bba78164bd9d3))
* increase version ([27e14fd](https://github.com/Akhrameev/dart-code-linter/commit/27e14fd881a7bfa32dd8930d0eb4301180f7e515))
* increase version 1.2.0 ([e110511](https://github.com/Akhrameev/dart-code-linter/commit/e1105112ff07a5aad07794972b093c06e2330979))
* **lint-analyzer:** apply fixes back-to-front to avoid RangeError on multiple fixes ([#188](https://github.com/Akhrameev/dart-code-linter/issues/188)) ([#246](https://github.com/Akhrameev/dart-code-linter/issues/246)) ([db411dd](https://github.com/Akhrameev/dart-code-linter/commit/db411dd9d4ee7655d20793b017086cdd34387be5))
* **lint-analyzer:** resolve ExtensionTypeDeclaration.primaryConstructor deprecation via ast_compat helper ([#249](https://github.com/Akhrameev/dart-code-linter/issues/249)) ([#252](https://github.com/Akhrameev/dart-code-linter/issues/252)) ([1d7eddc](https://github.com/Akhrameev/dart-code-linter/commit/1d7eddccb29c21e6be07ccd09127f322ef1505c0))
* list-all-equatable-fields should be typed common ([#1141](https://github.com/Akhrameev/dart-code-linter/issues/1141)) ([3130a85](https://github.com/Akhrameev/dart-code-linter/commit/3130a85af05c59f58034728b5a77b592d4f2a0a5))
* make avoid-border-all not report errors on final variables ([#988](https://github.com/Akhrameev/dart-code-linter/issues/988)) ([955ae2f](https://github.com/Akhrameev/dart-code-linter/commit/955ae2f739cc8215aee4508d6500883af33b3d28))
* make avoid-redundant-async correctly handle nullable return values ([#1009](https://github.com/Akhrameev/dart-code-linter/issues/1009)) ([1369ced](https://github.com/Akhrameev/dart-code-linter/commit/1369cedc2e48aeea4bf5dd020cb59003c713f719))
* make avoid-redundant-async handle yield ([#1021](https://github.com/Akhrameev/dart-code-linter/issues/1021)) ([2eec475](https://github.com/Akhrameev/dart-code-linter/commit/2eec4756bad7713bac7a8a8cfc5bec2c066f2268))
* make avoid-wrapping-in-padding trigger only on Container widget ([#1008](https://github.com/Akhrameev/dart-code-linter/issues/1008)) ([9ac53f1](https://github.com/Akhrameev/dart-code-linter/commit/9ac53f1300c97d81f00c95ca2649ca86a7d9fc22))
* make check-unnecessary-nullable command ignore Flutter keys ([#994](https://github.com/Akhrameev/dart-code-linter/issues/994)) ([81f521c](https://github.com/Akhrameev/dart-code-linter/commit/81f521c0b707531333468019c40dd8067eb87056))
* md files ([63992b2](https://github.com/Akhrameev/dart-code-linter/commit/63992b2f123ce2ab9fa3e521552b649a83e76588))
* md files ([09854a2](https://github.com/Akhrameev/dart-code-linter/commit/09854a20a1c4ba1a66ee2438d7c0a315de7d0321))
* **metrics:** respect per-line `// ignore:` comments for metric violations ([#236](https://github.com/Akhrameev/dart-code-linter/issues/236)) ([d2fbbc1](https://github.com/Akhrameev/dart-code-linter/commit/d2fbbc11152c38658b88f3c78467208f666b46d4))
* migrate lint_analyzer ([87c8785](https://github.com/Akhrameev/dart-code-linter/commit/87c8785cfa2a543dffa905934f9b0a6570dfdfa1))
* **no-magic-number:** remove self-reported parameter_assignments analyzer warnings ([#243](https://github.com/Akhrameev/dart-code-linter/issues/243)) ([1633fa7](https://github.com/Akhrameev/dart-code-linter/commit/1633fa716ccbce38a83a05f848b99a1b9d1532d6))
* override toJson for arguments-ordering ([5c06f67](https://github.com/Akhrameev/dart-code-linter/commit/5c06f6784bcee5c3925b669a245d620714fe4e82))
* partially handle normal completion function body for avoid-redundant-async ([#1148](https://github.com/Akhrameev/dart-code-linter/issues/1148)) ([7ce686f](https://github.com/Akhrameev/dart-code-linter/commit/7ce686fc2a37eb9ec6dcb1d1916cfb6e78d971cd))
* **prefer-dot-shorthands:** add support for unnamed constructors ([#266](https://github.com/Akhrameev/dart-code-linter/issues/266)) ([f684aec](https://github.com/Akhrameev/dart-code-linter/commit/f684aec04a2312f5776927ecda6731a41ab613b5))
* **prefer-moving-to-variable:** 4.0.3: detect duplicates in expression bodies + release process docs ([#219](https://github.com/Akhrameev/dart-code-linter/issues/219)) ([3e0f799](https://github.com/Akhrameev/dart-code-linter/commit/3e0f7992e7aa8df9f4a5570ba7050dc0ad7039bb))
* publish pipeline ([969bc67](https://github.com/Akhrameev/dart-code-linter/commit/969bc675302771bb0dbddcd2751bff9e89e6f35d))
* publish pipeline ([581e3f8](https://github.com/Akhrameev/dart-code-linter/commit/581e3f818109aed9b9f138fadc76211a4f73bdef))
* Recover example.dart with its empty lines for test to catch these issues ([43b7abc](https://github.com/Akhrameev/dart-code-linter/commit/43b7abca76f3a351991a2dff6df98fd681e7f52c))
* relax analyzer constraints for Flutter stable compatibility ([#228](https://github.com/Akhrameev/dart-code-linter/issues/228)) ([#229](https://github.com/Akhrameev/dart-code-linter/issues/229)) ([9771482](https://github.com/Akhrameev/dart-code-linter/commit/9771482d7e46a42f61ab6e32798d475b43096157))
* remove recursive traversal for ban-name ([#1090](https://github.com/Akhrameev/dart-code-linter/issues/1090)) ([54d50d5](https://github.com/Akhrameev/dart-code-linter/commit/54d50d58bd9cf1949067b1b11f8173a547fe70ca))
* remove unsafe_html linter rule and update element references ([84a9efa](https://github.com/Akhrameev/dart-code-linter/commit/84a9efa26720f415ba593c58415df6751ef751f6))
* report in IDES is adjusted ([18dfe82](https://github.com/Akhrameev/dart-code-linter/commit/18dfe82c453498cad44cf982b78ce056db4b0c0f))
* sdk environment ([b7c36a0](https://github.com/Akhrameev/dart-code-linter/commit/b7c36a0fef04e2eadc9cd5a5af698b2b1c272d95))
* sdk environment ([e5ce8b1](https://github.com/Akhrameev/dart-code-linter/commit/e5ce8b196e7cd0959cac7b09e0cf225df00f30e9))
* stop plugin flickering ([34aab1f](https://github.com/Akhrameev/dart-code-linter/commit/34aab1f3fb0e8e91df5828f8aa5b380b26d699ff))
* support assert(mounted) for use-setstate-synchronously ([#1181](https://github.com/Akhrameev/dart-code-linter/issues/1181)) ([cde4648](https://github.com/Akhrameev/dart-code-linter/commit/cde4648367cf5db59b1691fb763e224a9e239ef3))
* support configured plugin rules on Dart 3.13 ([#263](https://github.com/Akhrameev/dart-code-linter/issues/263)) ([6a20197](https://github.com/Akhrameev/dart-code-linter/commit/6a201970248f488f7304ffbdc88fc7cdf1676de6))
* support function expression invocations for prefer-moving-to-variable ([#1109](https://github.com/Akhrameev/dart-code-linter/issues/1109)) ([1c507fe](https://github.com/Akhrameev/dart-code-linter/commit/1c507fee1215d5eb764cbc2c3c495c0ba80c4269))
* support not named builder parameters for avoid-returning-widgets ([#992](https://github.com/Akhrameev/dart-code-linter/issues/992)) ([f0516ce](https://github.com/Akhrameev/dart-code-linter/commit/f0516ce646e1918bd5a27504a8472c6311dc40b2))
* support tear-off methods for check-unnecessary-nullable ([#1154](https://github.com/Akhrameev/dart-code-linter/issues/1154)) ([aa8bc9b](https://github.com/Akhrameev/dart-code-linter/commit/aa8bc9bdc3403af82f6ee2245d3c694d2b86a87e))
* support variables shadowing for avoid-unused-parameters ([#993](https://github.com/Akhrameev/dart-code-linter/issues/993)) ([d1812bb](https://github.com/Akhrameev/dart-code-linter/commit/d1812bbbe2478831cf99c89194f58a27eb9f51da))
* tests ([9fe8f64](https://github.com/Akhrameev/dart-code-linter/commit/9fe8f6422c89807999fc50557e2021f68751b9ef))
* tests ([87d7ce3](https://github.com/Akhrameev/dart-code-linter/commit/87d7ce3e618f7706d750aa0ecc410b0b1fe4666b))
* to publish in pub.dev ([5c35b94](https://github.com/Akhrameev/dart-code-linter/commit/5c35b94bae6c8bfddf68818424d7b18916804e2b))
* to publish in pub.dev ([f99fbe2](https://github.com/Akhrameev/dart-code-linter/commit/f99fbe2188251cfec9e9e86f807180d6ecb1a1a9))
* update DCL version in analyzer_plugin ([51c759d](https://github.com/Akhrameev/dart-code-linter/commit/51c759dd156f3f3bb75a77aa5e582924d00f1e99))
* update presets ([#1082](https://github.com/Akhrameev/dart-code-linter/issues/1082)) ([37902ea](https://github.com/Akhrameev/dart-code-linter/commit/37902eaa1fcf8f1131348dfb15df092842cf6af3))
* update progress correctly for idea ([ce0e429](https://github.com/Akhrameev/dart-code-linter/commit/ce0e429361e655447ee6302715967f36f63ebee4))
* update tear-off detection for unused-parameters rule ([050035e](https://github.com/Akhrameev/dart-code-linter/commit/050035eaa92a355aba17aec9fa615a08eb7a38de))
* update url ([fa5e93e](https://github.com/Akhrameev/dart-code-linter/commit/fa5e93eca90a66106a07070c66bc4a33c624eec9))
* update url ([d5423ee](https://github.com/Akhrameev/dart-code-linter/commit/d5423ee5cc801c9bd1e2602c8e82bc689a727047))
* use correct imports ([be18655](https://github.com/Akhrameev/dart-code-linter/commit/be18655f4626b41b9177d2083a6f0879a2b7ce5f))
* use empty analysis options exclude to properly resolve units and speed up commands analysis ([#998](https://github.com/Akhrameev/dart-code-linter/issues/998)) ([cfcd783](https://github.com/Akhrameev/dart-code-linter/commit/cfcd783b15f41857bf40015c96865f990f1bd9c7))
* use-setstate-synchronously edge cases ([#1128](https://github.com/Akhrameev/dart-code-linter/issues/1128)) ([0f3199e](https://github.com/Akhrameev/dart-code-linter/commit/0f3199e5e09c3c515fddce8c673359c9c79beebe))
* visit only widgets for use-setstate-synchronously ([e5615dc](https://github.com/Akhrameev/dart-code-linter/commit/e5615dc992cf04e419eb9c764247fc173d0be2a8))
* visit only widgets for use-setstate-synchronously ([#1210](https://github.com/Akhrameev/dart-code-linter/issues/1210)) ([b9c7b57](https://github.com/Akhrameev/dart-code-linter/commit/b9c7b575ffc5c92bf63d752c0c0870de20e18022))
* visitor and replacement ([617900b](https://github.com/Akhrameev/dart-code-linter/commit/617900b380890681a222717d2b8154392b362efe))

## 4.3.0
- Add opt-in detection of unused public members in type declarations to `check-unused-code`, enabled via the `--analyze-public-members` CLI flag or the `unused-code.analyze-public-members` analysis-options key and disabled by default. It is independent of `analyze-private-members`, so a large project can keep the cheaper private members check on while leaving this one off. Members that cannot be seen to be used through a reference are skipped instead of reported: members overriding or implementing an inherited member (found by walking `allSupertypes`, which also covers `toString`/`hashCode`/`noSuchMethod` and overrides written without `@override`), members carrying an annotation that says they are called from elsewhere (`@override`, `@mustBeOverridden`, `@visibleForOverriding`, `@redeclare`, `@protected`, `@visibleForTesting`, `@JS`, `@pragma('vm:entry-point')`), members exported to JavaScript with `@JSExport` (counted from the enclosing class too, but there only for its instance members, since a class level annotation never wraps statics; a class level `@pragma('vm:entry-point')` deliberately does not work this way at all, as it only permits allocation from native code and leaves members needing their own pragma), members whose name is invoked or read on a `dynamic` target anywhere in the program, `toJson` (called by `json.encode` rather than by reference), enum constants of an enum whose `values` is referenced, and unnamed constructors (their invocations carry no identifier to record; named constructors are analyzed).
- Record usages of members reached without an identifier: binary, index, unary and increment operator invocations (`a + b`, `a[b]`, `-a`, `a++`) and implicit `call` invocations previously marked only the enclosing extension as used, so a class's operators looked unused as soon as member analysis was on. The combiner of a compound assignment (`a += b`, which reaches `operator +`) was recorded nowhere at all, so an extension whose operator is used only that way was falsely reported even by the default top-level analysis. Operators and implicit `call` invocations on a `dynamic` target resolve to no element and are now recorded by the member name they reach, the same way dynamic method calls and property reads are.
- Fix the legacy analyzer plugin loader silently loading the wrong DCL version. The analysis server copies `tools/analyzer_plugin/pubspec.yaml` verbatim and resolves it against pub.dev, so its `dart_code_linter` range (frozen at `<4.2.0` since 4.1.7) resolved to 4.1.9 for anyone on 4.2.0 or later: the IDE ran 4.1.9's rules while the CLI ran the installed version, with no error, because a satisfying version always exists. Restored the exact version pin used up to 4.0.1, so each release's loader loads exactly that release.
- Fix a false negative in `check-unused-code` with `analyze-private-members` enabled: a used class member no longer marks a dead top-level declaration of the same name as used (a class calling its own `dispose` used to hide an unused top-level `dispose` function). The name based fallback that works around [dart-lang/sdk#49182](https://github.com/dart-lang/sdk/issues/49182) now requires both sides to agree on whether they are members, which cannot introduce false positives because member dispatch never resolves to a library level declaration.
- Document the `--analyze-private-members` flag and the `unused-code.analyze-private-members` analysis-options key in the README, including their precedence and known limitations.
- Extend the private members test coverage to mixin, enum and extension type members, static members, and member level `// ignore: unused-code` suppressions.
- Fix a false negative in `avoid-non-configurable-callbacks-in-init-state` where a named argument whose label reads `widget` or a known callback method name (e.g. `Options(widget: child)`) was mistaken for a real reference to the state's `widget` getter or to that method, suppressing the warning. Reproducible only on analyzer 10-12, where a named argument's label is a `Label`-wrapped identifier; analyzer 13+ uses a bare token for it instead.
- Fix a false negative in `avoid-non-exhaustive-switch-on-sealed-classes` where a parenthesized wildcard case (`case (_):`) was not recognized as defeating exhaustiveness the same way a bare `_` does.

## 4.2.2
- Fix Analysis Server plugin configuration loading across supported Dart runtimes.

## 4.2.1
- Fix `prefer-dot-shorthands` to also flag unnamed constructor calls (suggesting `.new(...)`) and enum/static member access used as a `switch` statement/expression case pattern matched against the switch's scrutinee type — both were previously left unflagged.

## 4.2.0
- Fix Analysis Server plugin rule configuration on Dart 3.13 by keeping plugin diagnostics scalar and loading full options from `dart_code_linter.rules`.
- Add the `avoid-non-configurable-callbacks-in-init-state` rule, which flags a `State.initState` that configures a widget-supplied object (e.g. `widget.controller.setNavigationDelegate(...)`) with a callback object whose named callbacks never reference the widget's own fields — a sign the behavior is fully hardcoded with no way for callers of the widget to customize it.
- Add the `avoid-non-exhaustive-switch-on-sealed-classes` rule, which flags a `default`/wildcard (`_`) case in a `switch` statement or expression over a sealed type. Relying on a fallback case defeats the compiler's exhaustiveness checking for sealed hierarchies, so newly added subtypes can silently fall through instead of forcing an explicit decision at each call site.
- Add the `prefer-dot-shorthands` rule (with auto-fix), which flags enum/static member access, static method calls, and named constructor calls that repeat a type name already inferable from context (a call argument's declared parameter type, or an explicitly typed variable's initializer) — Dart 3.10's dot-shorthand syntax lets these collapse to `.value` instead of `Type.value`. The rule only fires on files whose language version is 3.10 or later, since the shorthand syntax does not compile below that.

## 4.1.9
- Add opt-in detection of unused private members in type declarations (methods, fields, getters, setters and named constructors) to `check-unused-code`. Private members cannot be referenced from outside the declaring library, which rules out the reflection and cross-library false positives that make public members unreliable to analyze. Mirroring the SDK's `unused_element` semantics, a sole private constructor is never reported: it is the intentional prevent-instantiation/extension pattern (an entirely unused class is still reported by the class-level check). Enabled via the `--analyze-private-members` CLI flag or the `unused-code.analyze-private-members` analysis-options key; disabled by default.

## 4.1.8
- Raise the `analyzer` ceiling to `<15.0.0`, enabling analyzer 14.x support now that `dart_style` 3.1.11 added compatibility with it. Add 14.0.0 and 14.1.0 rows to the `scripts/test_analyzer_compat.py` matrix (`analyzer_plugin` 0.14.13/0.14.14, `analysis_server_plugin` 0.3.19/0.3.20).

## 4.1.7
- Replace the deprecated `Folder.getChildAssumingFile` with `ResourceProvider.getFile` in the analyzer plugin's UUID bootstrap, resolving the pana static-analysis deprecation warning on analyzer 13.x. The call stays compatible across the full `>=10.0.0 <14.0.0` range (`Folder.getFile` only exists in analyzer 13.3.0+).
- Replace the deprecated `MethodDeclaration.isAbstract` with a structural `ast_compat.isAbstractMethod()` helper in `avoid-unused-parameters`, keeping the call non-deprecated across the full `>=10.0.0 <14.0.0` range (`isComplete` only exists in analyzer 13.2+).

## 4.1.6
- Add an auto-fix to the `prefer-enums-by-name` rule that converts `Enum.values.firstWhere((e) => e.name == x)` to `Enum.values.byName(x)`. The fix is offered only when the call is safely convertible: a single-parameter `== name` arrow closure, no `orElse`, and a lookup that does not reference the closure parameter.
- Fix a deprecation warning for `ExtensionTypeDeclaration.primaryConstructor` (deprecated on analyzer 13.1+ in favor of `namePart`, which doesn't exist before 13.1) by reading the extension type's name structurally through a new `ast_compat` helper instead of the version-specific getter.

## 4.1.5
- Add an auto-fix to the `avoid-duplicate-exports` rule that deletes the duplicate export directive (the earlier export already covers the same URI, so the removal is behavior-preserving).
- Fix a `RangeError` crash in the `fix` command when a file had multiple auto-fixable issues; fixes are now applied from the end of the file towards the start so earlier edits no longer invalidate later offsets.

## 4.1.4
- Add an auto-fix to the `no-blank-line-before-single-return` rule that removes the blank line(s) before a single `return` statement in a block, preserving any comments.
- Fix a false positive in `no-blank-line-before-single-return` where a trailing comment on the block's opening brace (e.g. `{ // comment`) was reported even without a blank line before the return.

## 4.1.3
- Add an auto-fix to the `avoid-unnecessary-type-casts` rule that removes the redundant `as` cast (e.g. `value as String` becomes `value`).

## 4.1.2
- Remove two self-reported `parameter_assignments` analyzer warnings in the `no-magic-number` rule implementation by replacing `++count` with `count + 1` in the literal-counting callbacks (no behavioral change).

## 4.1.1
- Add config option `prefer-match-file-name.ignore-enums` and `prefer-match-file-name.ignore-typedefs` to suppress reports for enum and typedef declarations whose name doesn't match the file name.

## 4.1.0
- Add support for `analysis_server_plugin` (analyzer 13.x).
- Add support for `analyzer` 13.x via a cross-version AST shim ([lib/src/utils/ast_compat.dart](lib/src/utils/ast_compat.dart)) that recognises the reshaped named-argument, record-field, default-parameter and label nodes structurally.
- Widen `analyzer` constraint to `>=10.0.0 <14.0.0`.
- Extend `make test-analyzer-compat-full` to cover analyzer 10.x, 11.x, 12.x and 13.x; skip versions whose Dart SDK constraint is incompatible with the host SDK instead of failing.

## 4.0.5
- Add `ignored-invocations` and `ignored-targets` options to `prefer-moving-to-variable` rule to suppress reports for specific method/getter names or target receivers.
- Add autofix for `newline-before-return` with comment-aware, whitespace-preserving behavior and edge-case fixture coverage.

## 4.0.4
- Honor per-line `// ignore: <metric-id>` comments for function- and class-level metric violations (both leading and trailing forms). File-level metrics keep their `// ignore_for_file:` behavior.

## 4.0.3
- Fix `prefer-moving-to-variable` rule not detecting duplicate invocations in expression function bodies (`=> expr`).

## 4.0.2
- Update `packageVersion` constant to match pubspec version (was hardcoded as `3.2.0`).

## 4.0.1
- Relax `analyzer` constraint to >=10.0.0 <13.0.0 to support Flutter stable with `meta` 1.17.0.
- Relax `analyzer_plugin` constraint to >=0.14.0 <0.16.0.
- Add support for `analyzer` 12.x (replace removed `LibraryIdentifier` with version-agnostic approach).
- Remove `dependency_overrides` from main and example pubspecs.

## 4.0.0
- **BREAKING**: Update minimum Dart SDK to >=3.5.0 (compatible with Flutter 3.24+).
- Update `analyzer` to >=11.0.0 <12.0.0.
- Update `analyzer_plugin` to ^0.14.5.
- Fix element comparison for substituted elements in `always-remove-listener` rule.
- Add Packaged AI Assets for MCP integration (`extension/mcp/`).

## 3.2.1
- Update homepage in `pubspec.yaml`.

## 3.2.0
- Update `analyzer` constraint to ^8.2.0. Only works with `dart >= 3.9.0`.
- Add rule `use-design-system-items`.
- Add rule `only-barrel-import`.
- Allow to specify more than one suggestion for each rule.

## 3.2.0-alpha.2
- Update `analyzer` constraint to ^8.2.0

## 3.2.0-alpha.1
- Add rule `use-design-system-items`.
- Add rule `only-barrel-import`.
- Allow to specify more than one suggestion for each rule.
- Bump `analyzer` to ^8.0.0

## 3.1.1
- Changed `prefer-media-query-direct-access` to `FlutterRule`.

## 3.1.0
- Add rule `prefer-media-query-direct-access`.
- Add rule `prefer-named-record-fields`.

## 3.1.0-beta.3
- Add rule `prefer-media-query-direct-access`.

## 3.1.0-beta.2
- Fixed DCL version in analyzer_plugin.

## 3.1.0-beta.1
- Add rule `prefer-named-record-fields`.

## 3.0.0-beta.1
- [Breaking] Update dart sdk constraints to `>=3.4.0 <4.0.0`.
- Update `analyzer` to version ^7.4.4
## 2.0.0
- Update `analyzer` to version ^6.0.0
## 1.3.0
- Added `fatal-warnings-threshold` `fatal-performance-threshold` and `fatal-style-threshold` to set the failure threshold for analyze command
## 1.2.1
- Fixed generating report file when find issues in the report
## 1.2.0
- Added fix command
- Added prefer single quotes rule
- Added prefer first or null rule
- Added no blank line before single return rule
- Fixed rule avoid dynamic to extensions definition
## 1.1.5
- Removed deprecated fields in analysis options and collection method
- Fixed changelog URL for update available warning
## 1.1.4
- Fixed some test
- Reverted `analyzer` ^6.0.0 to ^5.14.0
## 1.1.3
- Fixed some test
## 1.1.2
- Append new presset `analysis_options.1.0.0.yaml`
## 1.1.1
- Rename common rules to dart rules
## 1.1.0
- Added new presets
- Removed Angular framework rules
- Added example

## 1.0.2
- Fix: report in IDE'S is adjusted
## 1.0.1
- Automated publishing of packages to pub.dev

## 1.0.0
- Fork: [Dart code metrics 5.7.3](https://github.com/dart-code-checker/dart-code-metrics)
