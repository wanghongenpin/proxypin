import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')
  ];

  /// No description provided for @requests.
  ///
  /// In en, this message translates to:
  /// **'Requests'**
  String get requests;

  /// No description provided for @favorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favorites;

  /// No description provided for @history.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get history;

  /// No description provided for @toolbox.
  ///
  /// In en, this message translates to:
  /// **'Toolbox'**
  String get toolbox;

  /// No description provided for @me.
  ///
  /// In en, this message translates to:
  /// **'Me'**
  String get me;

  /// No description provided for @preference.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get preference;

  /// No description provided for @feedback.
  ///
  /// In en, this message translates to:
  /// **'Feedback'**
  String get feedback;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @filter.
  ///
  /// In en, this message translates to:
  /// **'Proxy Filter'**
  String get filter;

  /// No description provided for @script.
  ///
  /// In en, this message translates to:
  /// **'Script'**
  String get script;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @port.
  ///
  /// In en, this message translates to:
  /// **'Port: '**
  String get port;

  /// No description provided for @proxy.
  ///
  /// In en, this message translates to:
  /// **'Proxy'**
  String get proxy;

  /// No description provided for @externalProxy.
  ///
  /// In en, this message translates to:
  /// **'External Proxy'**
  String get externalProxy;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @proxySetting.
  ///
  /// In en, this message translates to:
  /// **'Proxy Setting'**
  String get proxySetting;

  /// No description provided for @systemProxy.
  ///
  /// In en, this message translates to:
  /// **'Set as System Proxy'**
  String get systemProxy;

  /// No description provided for @enabledHTTP2.
  ///
  /// In en, this message translates to:
  /// **'Enable HTTP2'**
  String get enabledHTTP2;

  /// No description provided for @serverNotStart.
  ///
  /// In en, this message translates to:
  /// **'Proxy server not started'**
  String get serverNotStart;

  /// No description provided for @download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// No description provided for @start.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get start;

  /// No description provided for @stop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stop;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @httpsProxy.
  ///
  /// In en, this message translates to:
  /// **'HTTPS Proxy'**
  String get httpsProxy;

  /// No description provided for @setting.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get setting;

  /// No description provided for @mobileConnect.
  ///
  /// In en, this message translates to:
  /// **'Mobile Connect'**
  String get mobileConnect;

  /// No description provided for @connectRemote.
  ///
  /// In en, this message translates to:
  /// **'Connect Remote'**
  String get connectRemote;

  /// No description provided for @remoteDevice.
  ///
  /// In en, this message translates to:
  /// **'Remote Device'**
  String get remoteDevice;

  /// No description provided for @remoteDeviceList.
  ///
  /// In en, this message translates to:
  /// **'Remote Device List'**
  String get remoteDeviceList;

  /// No description provided for @myQRCode.
  ///
  /// In en, this message translates to:
  /// **'My QR Code'**
  String get myQRCode;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @followSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow System'**
  String get followSystem;

  /// No description provided for @themeColor.
  ///
  /// In en, this message translates to:
  /// **'Theme Color'**
  String get themeColor;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @autoStartup.
  ///
  /// In en, this message translates to:
  /// **'Auto Start Recording Traffic'**
  String get autoStartup;

  /// No description provided for @autoStartupDescribe.
  ///
  /// In en, this message translates to:
  /// **'Automatically start recording traffic when the program starts'**
  String get autoStartupDescribe;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copied;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @confirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm operation'**
  String get confirmTitle;

  /// No description provided for @confirmContent.
  ///
  /// In en, this message translates to:
  /// **'Are you sure about this operation?'**
  String get confirmContent;

  /// No description provided for @addSuccess.
  ///
  /// In en, this message translates to:
  /// **'Successfully added'**
  String get addSuccess;

  /// No description provided for @saveSuccess.
  ///
  /// In en, this message translates to:
  /// **'Saved successfully'**
  String get saveSuccess;

  /// No description provided for @operationSuccess.
  ///
  /// In en, this message translates to:
  /// **'Operation succeeded'**
  String get operationSuccess;

  /// No description provided for @import.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get import;

  /// No description provided for @importSuccess.
  ///
  /// In en, this message translates to:
  /// **'Import successful'**
  String get importSuccess;

  /// No description provided for @importFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed'**
  String get importFailed;

  /// No description provided for @export.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get export;

  /// No description provided for @exportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Export successful'**
  String get exportSuccess;

  /// No description provided for @deleteSuccess.
  ///
  /// In en, this message translates to:
  /// **'Delete successful'**
  String get deleteSuccess;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @fail.
  ///
  /// In en, this message translates to:
  /// **'fail'**
  String get fail;

  /// No description provided for @success.
  ///
  /// In en, this message translates to:
  /// **'success'**
  String get success;

  /// No description provided for @emptyData.
  ///
  /// In en, this message translates to:
  /// **'Empty Data'**
  String get emptyData;

  /// No description provided for @requestSuccess.
  ///
  /// In en, this message translates to:
  /// **'Request successful'**
  String get requestSuccess;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @modify.
  ///
  /// In en, this message translates to:
  /// **'Modify'**
  String get modify;

  /// No description provided for @responseType.
  ///
  /// In en, this message translates to:
  /// **'Response Type'**
  String get responseType;

  /// No description provided for @request.
  ///
  /// In en, this message translates to:
  /// **'Request'**
  String get request;

  /// No description provided for @response.
  ///
  /// In en, this message translates to:
  /// **'Response'**
  String get response;

  /// No description provided for @statusCode.
  ///
  /// In en, this message translates to:
  /// **'Status code'**
  String get statusCode;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @type.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get type;

  /// No description provided for @enable.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get enable;

  /// No description provided for @example.
  ///
  /// In en, this message translates to:
  /// **'Example: '**
  String get example;

  /// No description provided for @responseHeader.
  ///
  /// In en, this message translates to:
  /// **'Headers'**
  String get responseHeader;

  /// No description provided for @requestHeader.
  ///
  /// In en, this message translates to:
  /// **'Headers'**
  String get requestHeader;

  /// No description provided for @requestLine.
  ///
  /// In en, this message translates to:
  /// **'Request Line'**
  String get requestLine;

  /// No description provided for @requestMethod.
  ///
  /// In en, this message translates to:
  /// **'Request Method'**
  String get requestMethod;

  /// No description provided for @param.
  ///
  /// In en, this message translates to:
  /// **'Param'**
  String get param;

  /// No description provided for @replaceBodyWith.
  ///
  /// In en, this message translates to:
  /// **'Replace Body With:'**
  String get replaceBodyWith;

  /// No description provided for @redirectTo.
  ///
  /// In en, this message translates to:
  /// **'Redirect To:'**
  String get redirectTo;

  /// No description provided for @redirect.
  ///
  /// In en, this message translates to:
  /// **'Redirect'**
  String get redirect;

  /// No description provided for @cannotBeEmpty.
  ///
  /// In en, this message translates to:
  /// **'Cannot be empty'**
  String get cannotBeEmpty;

  /// No description provided for @requestRewriteList.
  ///
  /// In en, this message translates to:
  /// **'Request Rewrite List'**
  String get requestRewriteList;

  /// No description provided for @requestRewriteRule.
  ///
  /// In en, this message translates to:
  /// **'Request Rewrite Rule'**
  String get requestRewriteRule;

  /// No description provided for @requestRewriteEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable Request Rewrite'**
  String get requestRewriteEnable;

  /// No description provided for @action.
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get action;

  /// No description provided for @multiple.
  ///
  /// In en, this message translates to:
  /// **'Multiple'**
  String get multiple;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @disabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get disabled;

  /// No description provided for @requestRewriteDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete {size} rule(s)?'**
  String requestRewriteDeleteConfirm(Object size);

  /// No description provided for @useGuide.
  ///
  /// In en, this message translates to:
  /// **'Use Guide'**
  String get useGuide;

  /// No description provided for @pleaseEnter.
  ///
  /// In en, this message translates to:
  /// **'Please Enter'**
  String get pleaseEnter;

  /// No description provided for @click.
  ///
  /// In en, this message translates to:
  /// **'Click'**
  String get click;

  /// No description provided for @replace.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get replace;

  /// No description provided for @clickEdit.
  ///
  /// In en, this message translates to:
  /// **'Click Edit'**
  String get clickEdit;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @selectFile.
  ///
  /// In en, this message translates to:
  /// **'Select file'**
  String get selectFile;

  /// No description provided for @match.
  ///
  /// In en, this message translates to:
  /// **'Match'**
  String get match;

  /// No description provided for @value.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get value;

  /// No description provided for @matchRule.
  ///
  /// In en, this message translates to:
  /// **'Match Rule'**
  String get matchRule;

  /// No description provided for @emptyMatchAll.
  ///
  /// In en, this message translates to:
  /// **'Empty means match all'**
  String get emptyMatchAll;

  /// No description provided for @newBuilt.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get newBuilt;

  /// No description provided for @newFolder.
  ///
  /// In en, this message translates to:
  /// **'New Folder'**
  String get newFolder;

  /// No description provided for @enableSelect.
  ///
  /// In en, this message translates to:
  /// **'Enable Select'**
  String get enableSelect;

  /// No description provided for @disableSelect.
  ///
  /// In en, this message translates to:
  /// **'Disable Select'**
  String get disableSelect;

  /// No description provided for @deleteSelect.
  ///
  /// In en, this message translates to:
  /// **'Delete Select'**
  String get deleteSelect;

  /// No description provided for @testData.
  ///
  /// In en, this message translates to:
  /// **'Test Data'**
  String get testData;

  /// No description provided for @noChangesDetected.
  ///
  /// In en, this message translates to:
  /// **'No changes detected'**
  String get noChangesDetected;

  /// No description provided for @enterMatchData.
  ///
  /// In en, this message translates to:
  /// **'Enter the data to be matched'**
  String get enterMatchData;

  /// No description provided for @modifyRequestHeader.
  ///
  /// In en, this message translates to:
  /// **'Modify Header'**
  String get modifyRequestHeader;

  /// No description provided for @headerName.
  ///
  /// In en, this message translates to:
  /// **'Header Name'**
  String get headerName;

  /// No description provided for @headerValue.
  ///
  /// In en, this message translates to:
  /// **'Header Value'**
  String get headerValue;

  /// No description provided for @deleteHeaderConfirm.
  ///
  /// In en, this message translates to:
  /// **'Do you want to delete the request header?'**
  String get deleteHeaderConfirm;

  /// No description provided for @sequence.
  ///
  /// In en, this message translates to:
  /// **'All Requests'**
  String get sequence;

  /// No description provided for @domainList.
  ///
  /// In en, this message translates to:
  /// **'Domain List'**
  String get domainList;

  /// No description provided for @domainWhitelist.
  ///
  /// In en, this message translates to:
  /// **'Proxy Domain Whitelist'**
  String get domainWhitelist;

  /// No description provided for @domainBlacklist.
  ///
  /// In en, this message translates to:
  /// **'Proxy Domain Blacklist'**
  String get domainBlacklist;

  /// No description provided for @domainFilter.
  ///
  /// In en, this message translates to:
  /// **'Proxy Domain List'**
  String get domainFilter;

  /// No description provided for @appWhitelist.
  ///
  /// In en, this message translates to:
  /// **'App Whitelist'**
  String get appWhitelist;

  /// No description provided for @appWhitelistDescribe.
  ///
  /// In en, this message translates to:
  /// **'Only proxy Apps on the whitelist. If the whitelist is enabled, the blacklist will be invalid'**
  String get appWhitelistDescribe;

  /// No description provided for @appBlacklist.
  ///
  /// In en, this message translates to:
  /// **'App Blacklist'**
  String get appBlacklist;

  /// No description provided for @scanCode.
  ///
  /// In en, this message translates to:
  /// **'Scan Code Connect'**
  String get scanCode;

  /// No description provided for @addBlacklist.
  ///
  /// In en, this message translates to:
  /// **'Add Proxy Blacklist'**
  String get addBlacklist;

  /// No description provided for @addWhitelist.
  ///
  /// In en, this message translates to:
  /// **'Add Proxy Whitelist'**
  String get addWhitelist;

  /// No description provided for @deleteWhitelist.
  ///
  /// In en, this message translates to:
  /// **'Delete Proxy Whitelist'**
  String get deleteWhitelist;

  /// No description provided for @domainListSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Last Request Time: {time},  Count: {count}'**
  String domainListSubtitle(Object count, Object time);

  /// No description provided for @selectAction.
  ///
  /// In en, this message translates to:
  /// **'Select action'**
  String get selectAction;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @copyHost.
  ///
  /// In en, this message translates to:
  /// **'Copy Host'**
  String get copyHost;

  /// No description provided for @copyUrl.
  ///
  /// In en, this message translates to:
  /// **'Copy URL'**
  String get copyUrl;

  /// No description provided for @copyRawRequest.
  ///
  /// In en, this message translates to:
  /// **'Copy Raw Request'**
  String get copyRawRequest;

  /// No description provided for @copyRequestResponse.
  ///
  /// In en, this message translates to:
  /// **'Copy Request and Response'**
  String get copyRequestResponse;

  /// No description provided for @copyCurl.
  ///
  /// In en, this message translates to:
  /// **'Copy cURL'**
  String get copyCurl;

  /// No description provided for @copyAsPythonRequests.
  ///
  /// In en, this message translates to:
  /// **'Copy as Python Requests'**
  String get copyAsPythonRequests;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @repeat.
  ///
  /// In en, this message translates to:
  /// **'Repeat'**
  String get repeat;

  /// No description provided for @repeatAllRequests.
  ///
  /// In en, this message translates to:
  /// **'Repeat All Requests'**
  String get repeatAllRequests;

  /// No description provided for @repeatDomainRequests.
  ///
  /// In en, this message translates to:
  /// **'Repeat Domain Requests'**
  String get repeatDomainRequests;

  /// No description provided for @customRepeat.
  ///
  /// In en, this message translates to:
  /// **'Custom Repeat'**
  String get customRepeat;

  /// No description provided for @repeatCount.
  ///
  /// In en, this message translates to:
  /// **'Iterations'**
  String get repeatCount;

  /// No description provided for @repeatInterval.
  ///
  /// In en, this message translates to:
  /// **'Interval(ms)'**
  String get repeatInterval;

  /// No description provided for @repeatDelay.
  ///
  /// In en, this message translates to:
  /// **'Delay(ms)'**
  String get repeatDelay;

  /// No description provided for @scheduleTime.
  ///
  /// In en, this message translates to:
  /// **'Schedule Time'**
  String get scheduleTime;

  /// No description provided for @fixed.
  ///
  /// In en, this message translates to:
  /// **'fixed'**
  String get fixed;

  /// No description provided for @random.
  ///
  /// In en, this message translates to:
  /// **'random'**
  String get random;

  /// No description provided for @keepCustomSettings.
  ///
  /// In en, this message translates to:
  /// **'Keep custom settings'**
  String get keepCustomSettings;

  /// No description provided for @editRequest.
  ///
  /// In en, this message translates to:
  /// **'Edit and Request'**
  String get editRequest;

  /// No description provided for @reSendRequest.
  ///
  /// In en, this message translates to:
  /// **'The request has been resent'**
  String get reSendRequest;

  /// No description provided for @viewExport.
  ///
  /// In en, this message translates to:
  /// **'View Export'**
  String get viewExport;

  /// No description provided for @timeDesc.
  ///
  /// In en, this message translates to:
  /// **'Descending by time'**
  String get timeDesc;

  /// No description provided for @timeAsc.
  ///
  /// In en, this message translates to:
  /// **'Ascending by time'**
  String get timeAsc;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @clearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear Search'**
  String get clearSearch;

  /// No description provided for @requestType.
  ///
  /// In en, this message translates to:
  /// **'Request type'**
  String get requestType;

  /// No description provided for @keyword.
  ///
  /// In en, this message translates to:
  /// **'Keyword'**
  String get keyword;

  /// No description provided for @keywordSearchScope.
  ///
  /// In en, this message translates to:
  /// **'Keyword search scope: '**
  String get keywordSearchScope;

  /// No description provided for @favorite.
  ///
  /// In en, this message translates to:
  /// **'Favorite'**
  String get favorite;

  /// No description provided for @deleteFavorite.
  ///
  /// In en, this message translates to:
  /// **'Delete Favorite'**
  String get deleteFavorite;

  /// No description provided for @emptyFavorite.
  ///
  /// In en, this message translates to:
  /// **'Empty Favorite'**
  String get emptyFavorite;

  /// No description provided for @deleteFavoriteSuccess.
  ///
  /// In en, this message translates to:
  /// **'Favorite deleted'**
  String get deleteFavoriteSuccess;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @historyRecord.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historyRecord;

  /// No description provided for @historyCacheTime.
  ///
  /// In en, this message translates to:
  /// **'Cache Time'**
  String get historyCacheTime;

  /// No description provided for @historyManualSave.
  ///
  /// In en, this message translates to:
  /// **'Manual Save'**
  String get historyManualSave;

  /// No description provided for @historyDay.
  ///
  /// In en, this message translates to:
  /// **'{day} days'**
  String historyDay(Object day);

  /// No description provided for @historyForever.
  ///
  /// In en, this message translates to:
  /// **'Forever'**
  String get historyForever;

  /// No description provided for @historyRecordTitle.
  ///
  /// In en, this message translates to:
  /// **'{name} Records {length}'**
  String historyRecordTitle(Object length, Object name);

  /// No description provided for @historyEmptyName.
  ///
  /// In en, this message translates to:
  /// **'Name cannot be empty'**
  String get historyEmptyName;

  /// No description provided for @historySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Records {requestLength}  file {size}'**
  String historySubtitle(Object requestLength, Object size);

  /// No description provided for @historyUnSave.
  ///
  /// In en, this message translates to:
  /// **'Current record is not saved'**
  String get historyUnSave;

  /// No description provided for @historyDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Do you want to delete this history?'**
  String get historyDeleteConfirm;

  /// No description provided for @requestEdit.
  ///
  /// In en, this message translates to:
  /// **'Request Editing'**
  String get requestEdit;

  /// No description provided for @encode.
  ///
  /// In en, this message translates to:
  /// **'Encode'**
  String get encode;

  /// No description provided for @requestBody.
  ///
  /// In en, this message translates to:
  /// **'Request Body'**
  String get requestBody;

  /// No description provided for @responseBody.
  ///
  /// In en, this message translates to:
  /// **'Response Body'**
  String get responseBody;

  /// No description provided for @requestRewrite.
  ///
  /// In en, this message translates to:
  /// **'Request Rewrite'**
  String get requestRewrite;

  /// No description provided for @newWindow.
  ///
  /// In en, this message translates to:
  /// **'New Window'**
  String get newWindow;

  /// No description provided for @httpRequest.
  ///
  /// In en, this message translates to:
  /// **'HTTP Request'**
  String get httpRequest;

  /// No description provided for @enabledHttps.
  ///
  /// In en, this message translates to:
  /// **'Enable HTTPS Proxy'**
  String get enabledHttps;

  /// No description provided for @installRootCa.
  ///
  /// In en, this message translates to:
  /// **'Install Certificate'**
  String get installRootCa;

  /// No description provided for @installCaLocal.
  ///
  /// In en, this message translates to:
  /// **'Install Certificate to Local-Machine'**
  String get installCaLocal;

  /// No description provided for @downloadRootCa.
  ///
  /// In en, this message translates to:
  /// **'Download Certificate'**
  String get downloadRootCa;

  /// No description provided for @downloadRootCaNote.
  ///
  /// In en, this message translates to:
  /// **'Note: If you set the default browser to other than Safari, click this line to copy and paste the link to Safari browser'**
  String get downloadRootCaNote;

  /// No description provided for @generateCA.
  ///
  /// In en, this message translates to:
  /// **'Generate new root certificate'**
  String get generateCA;

  /// No description provided for @generateCADescribe.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to generate a new root certificate? If confirmed,\nYou need to reinstall and trust the new certificate'**
  String get generateCADescribe;

  /// No description provided for @resetDefaultCA.
  ///
  /// In en, this message translates to:
  /// **'Reset Default Root Certificate'**
  String get resetDefaultCA;

  /// No description provided for @resetDefaultCADescribe.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to reset to the default root certificate?\nProxyPin default root certificate is the same for all users.'**
  String get resetDefaultCADescribe;

  /// No description provided for @exportCaP12.
  ///
  /// In en, this message translates to:
  /// **'Export Root Certificate(.p12)'**
  String get exportCaP12;

  /// No description provided for @importCaP12.
  ///
  /// In en, this message translates to:
  /// **'Import Root Certificate(.p12)'**
  String get importCaP12;

  /// No description provided for @trustCa.
  ///
  /// In en, this message translates to:
  /// **'Trust Certificate'**
  String get trustCa;

  /// No description provided for @profileDownload.
  ///
  /// In en, this message translates to:
  /// **'Profile Download'**
  String get profileDownload;

  /// No description provided for @exportCA.
  ///
  /// In en, this message translates to:
  /// **'Export Root Certificate'**
  String get exportCA;

  /// No description provided for @exportPrivateKey.
  ///
  /// In en, this message translates to:
  /// **'Export Private Key'**
  String get exportPrivateKey;

  /// No description provided for @install.
  ///
  /// In en, this message translates to:
  /// **'Install'**
  String get install;

  /// No description provided for @installCaDescribe.
  ///
  /// In en, this message translates to:
  /// **'Install CA Setting > Profile Download > Install'**
  String get installCaDescribe;

  /// No description provided for @trustCaDescribe.
  ///
  /// In en, this message translates to:
  /// **'Trust CA Setting > General > About > Certificate Trust Setting'**
  String get trustCaDescribe;

  /// No description provided for @androidRoot.
  ///
  /// In en, this message translates to:
  /// **'System Certificate (ROOT Device)'**
  String get androidRoot;

  /// No description provided for @androidRootMagisk.
  ///
  /// In en, this message translates to:
  /// **'Magisk module: \nAndroid ROOT devices can be used Magisk ProxyPinCA System Certificate Module, After installing and restarting the phone Check the system certificate to see if there is a ProxyPinCA certificate. If there is, it indicates that the certificate has been successfully installed。'**
  String get androidRootMagisk;

  /// No description provided for @androidRootRename.
  ///
  /// In en, this message translates to:
  /// **'If the module does not take effect, you can install the system root certificate according to the online tutorial, and name the root certificate {name}'**
  String androidRootRename(Object name);

  /// No description provided for @androidRootCADownload.
  ///
  /// In en, this message translates to:
  /// **'Download System Certificate(.0)'**
  String get androidRootCADownload;

  /// No description provided for @androidUserCA.
  ///
  /// In en, this message translates to:
  /// **'User Certificate'**
  String get androidUserCA;

  /// No description provided for @androidUserCATips.
  ///
  /// In en, this message translates to:
  /// **'Tips: Android7+ many apps will not trust user certificates'**
  String get androidUserCATips;

  /// No description provided for @androidUserCAInstall.
  ///
  /// In en, this message translates to:
  /// **'Open settings -> Security -> Encryption and credentials -> Install certificate -> CA certificate'**
  String get androidUserCAInstall;

  /// No description provided for @androidUserXposed.
  ///
  /// In en, this message translates to:
  /// **'It is recommended to use the Xposed module for packet capture (no need for ROOT), click to view wiki'**
  String get androidUserXposed;

  /// No description provided for @configWifiProxy.
  ///
  /// In en, this message translates to:
  /// **'Configure mobile Wi-Fi proxy'**
  String get configWifiProxy;

  /// No description provided for @caInstallGuide.
  ///
  /// In en, this message translates to:
  /// **'Certificate Installation Guide'**
  String get caInstallGuide;

  /// No description provided for @caAndroidBrowser.
  ///
  /// In en, this message translates to:
  /// **'Open Google Browser on Android devices：'**
  String get caAndroidBrowser;

  /// No description provided for @caIosBrowser.
  ///
  /// In en, this message translates to:
  /// **'Open Safari on iOS devices：'**
  String get caIosBrowser;

  /// No description provided for @localIP.
  ///
  /// In en, this message translates to:
  /// **'Local IP '**
  String get localIP;

  /// No description provided for @mobileScan.
  ///
  /// In en, this message translates to:
  /// **'Configure Wi-Fi proxy or Scan with Mobile App'**
  String get mobileScan;

  /// No description provided for @decode.
  ///
  /// In en, this message translates to:
  /// **'Decode'**
  String get decode;

  /// No description provided for @encodeInput.
  ///
  /// In en, this message translates to:
  /// **'Enter the content to be converted'**
  String get encodeInput;

  /// No description provided for @encodeResult.
  ///
  /// In en, this message translates to:
  /// **'Conversion Result'**
  String get encodeResult;

  /// No description provided for @encodeFail.
  ///
  /// In en, this message translates to:
  /// **'Encoding failed'**
  String get encodeFail;

  /// No description provided for @decodeFail.
  ///
  /// In en, this message translates to:
  /// **'Decoding failed'**
  String get decodeFail;

  /// No description provided for @shareUrl.
  ///
  /// In en, this message translates to:
  /// **'Share Request URL'**
  String get shareUrl;

  /// No description provided for @shareCurl.
  ///
  /// In en, this message translates to:
  /// **'Share cURL Request'**
  String get shareCurl;

  /// No description provided for @shareRequestResponse.
  ///
  /// In en, this message translates to:
  /// **'Share Request and Response'**
  String get shareRequestResponse;

  /// No description provided for @captureDetail.
  ///
  /// In en, this message translates to:
  /// **'Capture Detail'**
  String get captureDetail;

  /// No description provided for @proxyPinSoftware.
  ///
  /// In en, this message translates to:
  /// **'ProxyPin Open source traffic capture software for all platforms'**
  String get proxyPinSoftware;

  /// No description provided for @prompt.
  ///
  /// In en, this message translates to:
  /// **'Prompt'**
  String get prompt;

  /// No description provided for @curlSchemeRequest.
  ///
  /// In en, this message translates to:
  /// **'If the curl format is recognized, should it be converted into an HTTP request?'**
  String get curlSchemeRequest;

  /// No description provided for @appExitTips.
  ///
  /// In en, this message translates to:
  /// **'Press again to exit the program'**
  String get appExitTips;

  /// No description provided for @remoteConnectDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Check remote connection failed, disconnected'**
  String get remoteConnectDisconnect;

  /// No description provided for @reconnect.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get reconnect;

  /// No description provided for @remoteConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected {os}, traffic will be forwarded to {os}'**
  String remoteConnected(Object os);

  /// No description provided for @remoteConnectForward.
  ///
  /// In en, this message translates to:
  /// **'Remote connection, forwarding requests to other terminals'**
  String get remoteConnectForward;

  /// No description provided for @connectSuccess.
  ///
  /// In en, this message translates to:
  /// **'Connect successful'**
  String get connectSuccess;

  /// No description provided for @connectedRemote.
  ///
  /// In en, this message translates to:
  /// **'Connected to remote'**
  String get connectedRemote;

  /// No description provided for @connected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connected;

  /// No description provided for @notConnected.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get notConnected;

  /// No description provided for @disconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnect;

  /// No description provided for @ipLayerProxy.
  ///
  /// In en, this message translates to:
  /// **'IP Layer Proxy(Beta)'**
  String get ipLayerProxy;

  /// No description provided for @ipLayerProxyDesc.
  ///
  /// In en, this message translates to:
  /// **'IP layer proxy can capture Flutter app requests, currently not very stable, welcome to submit PR'**
  String get ipLayerProxyDesc;

  /// No description provided for @inputAddress.
  ///
  /// In en, this message translates to:
  /// **'Input Address'**
  String get inputAddress;

  /// No description provided for @syncConfig.
  ///
  /// In en, this message translates to:
  /// **'Sync configuration'**
  String get syncConfig;

  /// No description provided for @pullConfigFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to pull configuration, please check the network connection'**
  String get pullConfigFail;

  /// No description provided for @sync.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get sync;

  /// No description provided for @invalidQRCode.
  ///
  /// In en, this message translates to:
  /// **'Unrecognized QR code'**
  String get invalidQRCode;

  /// No description provided for @remoteConnectFail.
  ///
  /// In en, this message translates to:
  /// **'Connection failed，Please check if it is allowed on the same LAN and firewall, iOS needs to enable local network permissions'**
  String get remoteConnectFail;

  /// No description provided for @remoteConnectSuccessTips.
  ///
  /// In en, this message translates to:
  /// **'Your phone needs to enable packet capture in order to capture requests'**
  String get remoteConnectSuccessTips;

  /// No description provided for @windowMode.
  ///
  /// In en, this message translates to:
  /// **'Window Mode'**
  String get windowMode;

  /// No description provided for @windowModeSubTitle.
  ///
  /// In en, this message translates to:
  /// **'Enabled Packet Capture, Enter the background, Display a small window'**
  String get windowModeSubTitle;

  /// No description provided for @pipIcon.
  ///
  /// In en, this message translates to:
  /// **'Window shortcut icon'**
  String get pipIcon;

  /// No description provided for @pipIconDescribe.
  ///
  /// In en, this message translates to:
  /// **'Show quick access to small window Icon'**
  String get pipIconDescribe;

  /// No description provided for @headerExpanded.
  ///
  /// In en, this message translates to:
  /// **'Headers Expanded'**
  String get headerExpanded;

  /// No description provided for @headerExpandedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Details page Headers is expanded by default'**
  String get headerExpandedSubtitle;

  /// No description provided for @bottomNavigation.
  ///
  /// In en, this message translates to:
  /// **'Bottom Navigation'**
  String get bottomNavigation;

  /// No description provided for @bottomNavigationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Bottom navigation bar is displayed, effective after restart'**
  String get bottomNavigationSubtitle;

  /// No description provided for @memoryCleanup.
  ///
  /// In en, this message translates to:
  /// **'Memory Cleanup'**
  String get memoryCleanup;

  /// No description provided for @memoryCleanupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Automatically clean up requests on memory limit reached and keep 32 most recent after cleaning'**
  String get memoryCleanupSubtitle;

  /// No description provided for @unlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get unlimited;

  /// No description provided for @custom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get custom;

  /// No description provided for @externalProxyAuth.
  ///
  /// In en, this message translates to:
  /// **'Proxy Auth (Optional)'**
  String get externalProxyAuth;

  /// No description provided for @externalProxyServer.
  ///
  /// In en, this message translates to:
  /// **'Proxy Server'**
  String get externalProxyServer;

  /// No description provided for @externalProxyConnectFailure.
  ///
  /// In en, this message translates to:
  /// **'External Proxy Connect failure'**
  String get externalProxyConnectFailure;

  /// No description provided for @externalProxyFailureConfirm.
  ///
  /// In en, this message translates to:
  /// **'Access to all http will fail due to network connectivity issues，Do you want to continue setting up external proxies。'**
  String get externalProxyFailureConfirm;

  /// No description provided for @mobileDisplayPacketCapture.
  ///
  /// In en, this message translates to:
  /// **'Mobile Display Packet Capture:'**
  String get mobileDisplayPacketCapture;

  /// No description provided for @proxyPortRepeat.
  ///
  /// In en, this message translates to:
  /// **'Startup failed, please check the port number {port} is occupied。'**
  String proxyPortRepeat(Object port);

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @proxyIgnoreDomain.
  ///
  /// In en, this message translates to:
  /// **'Proxy ignores domain'**
  String get proxyIgnoreDomain;

  /// No description provided for @domainWhitelistDescribe.
  ///
  /// In en, this message translates to:
  /// **'Only proxy domain names on the whitelist. If the whitelist is enabled, the blacklist will be invalid'**
  String get domainWhitelistDescribe;

  /// No description provided for @domainBlacklistDescribe.
  ///
  /// In en, this message translates to:
  /// **'Domain names on the blacklist will not be proxied'**
  String get domainBlacklistDescribe;

  /// No description provided for @domain.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get domain;

  /// No description provided for @enableScript.
  ///
  /// In en, this message translates to:
  /// **'Enable Script'**
  String get enableScript;

  /// No description provided for @scriptUseDescribe.
  ///
  /// In en, this message translates to:
  /// **'Use JavaScript to modify requests and responses'**
  String get scriptUseDescribe;

  /// No description provided for @scriptEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit script'**
  String get scriptEdit;

  /// No description provided for @scrollEnd.
  ///
  /// In en, this message translates to:
  /// **'Scroll to End'**
  String get scrollEnd;

  /// No description provided for @logger.
  ///
  /// In en, this message translates to:
  /// **'Log'**
  String get logger;

  /// No description provided for @material3.
  ///
  /// In en, this message translates to:
  /// **'Material 3 is the latest version of Google’s open-source design system'**
  String get material3;

  /// No description provided for @iosVpnBackgroundAudio.
  ///
  /// In en, this message translates to:
  /// **'After turning on packet capture, exit to the background. In order to maintain the main UI thread for network communication, a silent audio playback will be enabled to keep the main thread running. Otherwise, it will only run in the background for 30 seconds. Do you agree to play audio in the background after turning on packet capture?'**
  String get iosVpnBackgroundAudio;

  /// No description provided for @markRead.
  ///
  /// In en, this message translates to:
  /// **'Mark as read'**
  String get markRead;

  /// No description provided for @autoRead.
  ///
  /// In en, this message translates to:
  /// **'Auto read'**
  String get autoRead;

  /// No description provided for @highlight.
  ///
  /// In en, this message translates to:
  /// **'Highlight'**
  String get highlight;

  /// No description provided for @blue.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get blue;

  /// No description provided for @green.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get green;

  /// No description provided for @yellow.
  ///
  /// In en, this message translates to:
  /// **'Yellow'**
  String get yellow;

  /// No description provided for @red.
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get red;

  /// No description provided for @pink.
  ///
  /// In en, this message translates to:
  /// **'Pink'**
  String get pink;

  /// No description provided for @gray.
  ///
  /// In en, this message translates to:
  /// **'Gray'**
  String get gray;

  /// No description provided for @underline.
  ///
  /// In en, this message translates to:
  /// **'Underline'**
  String get underline;

  /// No description provided for @requestBlock.
  ///
  /// In en, this message translates to:
  /// **'Request Block'**
  String get requestBlock;

  /// No description provided for @other.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get other;

  /// No description provided for @certHashName.
  ///
  /// In en, this message translates to:
  /// **'CA Hash Name'**
  String get certHashName;

  /// No description provided for @regExp.
  ///
  /// In en, this message translates to:
  /// **'RegExp'**
  String get regExp;

  /// No description provided for @systemCertName.
  ///
  /// In en, this message translates to:
  /// **'System Certificate Name'**
  String get systemCertName;

  /// No description provided for @qrCode.
  ///
  /// In en, this message translates to:
  /// **'QR Code'**
  String get qrCode;

  /// No description provided for @scanQrCode.
  ///
  /// In en, this message translates to:
  /// **'Scan QR Code'**
  String get scanQrCode;

  /// No description provided for @generateQrCode.
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get generateQrCode;

  /// No description provided for @saveImage.
  ///
  /// In en, this message translates to:
  /// **'Save Image'**
  String get saveImage;

  /// No description provided for @selectImage.
  ///
  /// In en, this message translates to:
  /// **'Select Image'**
  String get selectImage;

  /// No description provided for @inputContent.
  ///
  /// In en, this message translates to:
  /// **'Input Content'**
  String get inputContent;

  /// No description provided for @errorCorrectLevel.
  ///
  /// In en, this message translates to:
  /// **'Error Correct'**
  String get errorCorrectLevel;

  /// No description provided for @output.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get output;

  /// No description provided for @timestamp.
  ///
  /// In en, this message translates to:
  /// **'Timestamp'**
  String get timestamp;

  /// No description provided for @convert.
  ///
  /// In en, this message translates to:
  /// **'Convert'**
  String get convert;

  /// No description provided for @time.
  ///
  /// In en, this message translates to:
  /// **'DateTime'**
  String get time;

  /// No description provided for @nowTimestamp.
  ///
  /// In en, this message translates to:
  /// **'Now timestamp'**
  String get nowTimestamp;

  /// No description provided for @hosts.
  ///
  /// In en, this message translates to:
  /// **'Hosts'**
  String get hosts;

  /// No description provided for @toAddress.
  ///
  /// In en, this message translates to:
  /// **'To Address'**
  String get toAddress;

  /// No description provided for @encrypt.
  ///
  /// In en, this message translates to:
  /// **'Encrypt'**
  String get encrypt;

  /// No description provided for @decrypt.
  ///
  /// In en, this message translates to:
  /// **'Decrypt'**
  String get decrypt;

  /// No description provided for @cipher.
  ///
  /// In en, this message translates to:
  /// **'Cipher'**
  String get cipher;

  /// No description provided for @appUpdateCheckVersion.
  ///
  /// In en, this message translates to:
  /// **'Check for Updates'**
  String get appUpdateCheckVersion;

  /// No description provided for @appUpdateNotAvailableMsg.
  ///
  /// In en, this message translates to:
  /// **'Already Using The Latest Version'**
  String get appUpdateNotAvailableMsg;

  /// No description provided for @appUpdateDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Update Available'**
  String get appUpdateDialogTitle;

  /// No description provided for @appUpdateUpdateMsg.
  ///
  /// In en, this message translates to:
  /// **'A new version of ProxyPin is available. Would you like to update now?'**
  String get appUpdateUpdateMsg;

  /// No description provided for @appUpdateCurrentVersionLbl.
  ///
  /// In en, this message translates to:
  /// **'Current Version'**
  String get appUpdateCurrentVersionLbl;

  /// No description provided for @appUpdateNewVersionLbl.
  ///
  /// In en, this message translates to:
  /// **'New Version'**
  String get appUpdateNewVersionLbl;

  /// No description provided for @appUpdateUpdateNowBtnTxt.
  ///
  /// In en, this message translates to:
  /// **'Update Now'**
  String get appUpdateUpdateNowBtnTxt;

  /// No description provided for @appUpdateLaterBtnTxt.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get appUpdateLaterBtnTxt;

  /// No description provided for @appUpdateIgnoreBtnTxt.
  ///
  /// In en, this message translates to:
  /// **'Ignore'**
  String get appUpdateIgnoreBtnTxt;

  /// No description provided for @requestMap.
  ///
  /// In en, this message translates to:
  /// **'Request Map'**
  String get requestMap;

  /// No description provided for @requestMapDescribe.
  ///
  /// In en, this message translates to:
  /// **'Do not request remote services, use local configuration or script for response'**
  String get requestMapDescribe;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+script codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.scriptCode) {
          case 'Hant':
            return AppLocalizationsZhHant();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError('AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
