import 'package:proxypin/network/util/uri.dart';

void main() {
  String url =
      "https://edith.xiaohongshu.com/api/sns/v6/homefeed?client_volume=0.25&geo=eyJsYXRpdHVkZSI6NDAuMDU5MDkxOTAyNzk4OSwibG9uZ2l0dWRlIjoxMTYuNDEwMjA2OTMzNDYyN30%3D&known_signal=%7B%22nqe_level%22%3A6%2C%22hp_con%22%3A0%2C%22device_level%22%3A1%2C%22m_active%22%3A0%2C%22device_model%22%3A%22iPhone%2013%20Pro%22%2C%22hp_type%22%3A0%2C%22g_speed_y%22%3A1487.474609375%7D&last_card_position=4&last_live_id=&last_live_position=-1&loaded_ad=%7B%22loaded_ad_pos_list%22%3A%5B%5D%2C%22loaded_ad_real_pos_list%22%3A%5B%5D%2C%22ads_id_list%22%3A%5B%22663966499%22%2C%22243351939%22%2C%22230561227%22%5D%7D&num=20&oid=homefeed_recommend&orientation=portait&personalization=1&refresh_type=1&unread_begin_note_id=67136eaa0000000026034b5b&unread_end_note_id=67307eaf000000003c019503&unread_note_count=6&use_jpeg=1&user_action=0";
  print(url);
  var uri = Uri.parse(url);
  print(uri.queryParameters);

  print(uri);
  String query =
      '{"nqe_level":6,"hp_con":0,"device_level":1,"m_active":0,"device_model":"iPhone 13 Pro","hp_type":0,"g_speed_y":1487.474609375}';

  print(Uri.encodeComponent(query));
  // var splitQueryString = Uri.splitQueryString(uri.query);
  print(UriUtils.mapToQuery(uri.queryParameters));
  // print(uri.replace(queryParameters: splitQueryString));
  print(uri.replace(query: UriUtils.mapToQuery(uri.queryParameters)));
}
