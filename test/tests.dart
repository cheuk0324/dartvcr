import 'dart:math';

import 'package:dartvcr/src/advanced_settings.dart';
import 'package:dartvcr/src/cassette.dart';
import 'package:dartvcr/src/censor_element.dart';
import 'package:dartvcr/src/censors.dart';
import 'package:dartvcr/src/easyvcr_client.dart';
import 'package:dartvcr/src/expiration_actions.dart';
import 'package:dartvcr/src/match_rules.dart';
import 'package:dartvcr/src/mode.dart';
import 'package:dartvcr/src/time_frame.dart';
import 'package:dartvcr/src/utilities.dart';
import 'package:dartvcr/src/vcr.dart';
import 'package:dartvcr/src/vcr_exception.dart';
import 'package:test/test.dart';

import 'package:http/http.dart' as http;

import 'fake_data_service.dart';
import 'ip_address_data.dart';
import 'test_utils.dart';

Future<IPAddressData?> getIPAddressDataRequest(
    Cassette cassette, Mode mode) async {
  EasyVCRClient client = EasyVCRClient(cassette, mode,
      advancedSettings:
          AdvancedSettings(matchRules: MatchRules.defaultStrictMatchRules));

  FakeDataService service = FakeDataService("json", client: client);

  return await service.getIPAddressData();
}

Future<http.StreamedResponse> getIPAddressDataRawRequest(
    Cassette cassette, Mode mode) async {
  EasyVCRClient client = EasyVCRClient(cassette, mode,
      advancedSettings:
          AdvancedSettings(matchRules: MatchRules.defaultStrictMatchRules));

  FakeDataService service = FakeDataService("json", client: client);

  return await service.getIPAddressDataRawResponse();
}

void main() {
  group('Client tests', () {
    setUp(() {
      // Additional setup goes here.
    });

    test('Auto mode test', () async {
      Cassette cassette = TestUtils.getCassette("test_auto_mode");
      cassette.erase(); // Erase cassette before recording

      // in replay mode, if cassette is empty, should throw an exception
      expect(() => getIPAddressDataRequest(cassette, Mode.replay),
          throwsA(isA<VCRException>()));
      assert(cassette.numberOfInteractions ==
          0); // Make sure cassette is still empty

      // in auto mode, if cassette is empty, should make and record a real request
      IPAddressData? data = await getIPAddressDataRequest(cassette, Mode.auto);
      assert(data != null);
      assert(data!.ipAddress != null);
      assert(cassette.numberOfInteractions >
          0); // Make sure cassette is no longer empty
    });

    test('Read stream test', () async {
      Cassette cassette = TestUtils.getCassette("test_read_stream");
      cassette.erase(); // Erase cassette before recording

      IPAddressData? data =
          await getIPAddressDataRequest(cassette, Mode.record);

      // if we've gotten here, it means we've recorded an interaction (requiring a read of the stream),
      // and then read the stream again to deserialize the response
      assert(data != null);

      // just to be certain
      cassette.erase();
      assert(cassette.numberOfInteractions == 0);
      http.StreamedResponse response =
          await getIPAddressDataRawRequest(cassette, Mode.record);
      assert((await response.stream.bytesToString()).isNotEmpty);
    });

    test('Censors test', () async {
      Cassette cassette = TestUtils.getCassette("test_censors");
      cassette.erase(); // Erase cassette before recording

      // set up advanced settings
      String censorString = "censored-by-test";
      AdvancedSettings advancedSettings = AdvancedSettings(
          censors: Censors(censorString: censorString)
              .censorHeaderElementsByKeys(["date"]));

      // record cassette with advanced settings first
      EasyVCRClient client = EasyVCRClient(cassette, Mode.record,
          advancedSettings: advancedSettings);
      FakeDataService service = FakeDataService("json", client: client);
      await service.getIPAddressDataRawResponse();

      // now replay cassette
      client = EasyVCRClient(cassette, Mode.replay,
          advancedSettings: advancedSettings);
      service = FakeDataService("json", client: client);
      http.StreamedResponse response =
          await service.getIPAddressDataRawResponse();

      // check that the replayed response contains the censored header
      Map<String, String> headers = response.headers;
      assert(headers.containsKey("date"));
      assert(headers["date"] == censorString);
    });

    test('Default request matching test', () async {
      // test that match by method and url works
      Cassette cassette =
          TestUtils.getCassette("test_default_request_matching");
      cassette.erase(); // Erase cassette before recording

      Uri url = Uri.parse("https://google.com");
      String postBody = "test post body";

      // record cassette first
      EasyVCRClient client = EasyVCRClient(cassette, Mode.record,
          advancedSettings: AdvancedSettings(
              matchRules: MatchRules
                  .defaultMatchRules) // doesn't really matter for initial record
          );
      http.Response response = await client.post(url, body: postBody);
      assert(responseCameFromRecording(response) == false);

      // replay cassette
      client = EasyVCRClient(cassette, Mode.replay,
          advancedSettings:
              AdvancedSettings(matchRules: MatchRules.defaultMatchRules));
      response = await client.post(url, body: postBody);

      // check that the request body was matched and that a recording was used
      assert(responseCameFromRecording(response) == true);
    });

    test('Delay test', () async {
      Cassette cassette = TestUtils.getCassette("test_delay");
      cassette.erase(); // Erase cassette before recording

      // record cassette first
      EasyVCRClient client = EasyVCRClient(cassette, Mode.record);
      FakeDataService service = FakeDataService("json", client: client);
      await service.getIPAddressDataRawResponse();

      // baseline - how much time does it take to replay the cassette?
      client = EasyVCRClient(cassette, Mode.replay);
      service = FakeDataService("json", client: client);
      Stopwatch stopwatch = Stopwatch()..start();
      await service.getIPAddressDataRawResponse();
      stopwatch.stop();

      // note normal playback time
      int normalReplayTime = max(0, stopwatch.elapsedMilliseconds);

      // set up advanced settings
      int delay = normalReplayTime +
          3000; // add 3 seconds to the normal replay time, for good measure
      client = EasyVCRClient(cassette, Mode.replay,
          advancedSettings: AdvancedSettings(manualDelay: delay));
      service = FakeDataService("json", client: client);

      // time replay request
      stopwatch = Stopwatch()..start();
      await service.getIPAddressDataRawResponse();
      stopwatch.stop();

      // check that the delay was respected (within margin of error)
      int forcedReplayTime = max(0, stopwatch.elapsedMilliseconds);
      double requestedDelayWithMarginOfError =
          (delay * 0.95); // allow for 5% margin of error
      assert(forcedReplayTime >= requestedDelayWithMarginOfError);
    });

    test('Erase test', () async {
      Cassette cassette = TestUtils.getCassette("test_erase");

      // record something to the cassette
      EasyVCRClient client = EasyVCRClient(cassette, Mode.record);
      FakeDataService service = FakeDataService("json", client: client);
      await service.getIPAddressDataRawResponse();

      // make sure the cassette is no longer empty
      assert(cassette.numberOfInteractions > 0);

      // erase the cassette
      cassette.erase();

      // make sure the cassette is now empty
      assert(cassette.numberOfInteractions == 0);
    });

    test('Erase and playback test', () async {
      Cassette cassette = TestUtils.getCassette("test_erase_and_playback");
      cassette.erase(); // Erase cassette before recording

      // cassette is empty, so replaying should throw an exception
      EasyVCRClient client = EasyVCRClient(cassette, Mode.replay);
      FakeDataService service = FakeDataService("json", client: client);
      expect(service.getIPAddressDataRawResponse(), throwsException);
    });

    test('Erase and record test', () async {
      Cassette cassette = TestUtils.getCassette("test_erase_and_record");
      cassette.erase(); // Erase cassette before recording

      // cassette is empty, so recording should work
      EasyVCRClient client = EasyVCRClient(cassette, Mode.record);
      FakeDataService service = FakeDataService("json", client: client);
      await service.getIPAddressDataRawResponse();

      // make sure the cassette is no longer empty
      assert(cassette.numberOfInteractions > 0);
    });

    test('Expiration settings test', () async {
      Cassette cassette = TestUtils.getCassette("test_expiration_settings");
      cassette.erase(); // Erase cassette before recording

      Uri url = Uri.parse("https://google.com");

      // record cassette first
      EasyVCRClient client = EasyVCRClient(cassette, Mode.record);
      FakeDataService service = FakeDataService("json", client: client);
      await client.post(url);

      // replay cassette with default expiration rules, should find a match
      client = EasyVCRClient(cassette, Mode.replay);
      service = FakeDataService("json", client: client);
      http.Response response = await client.post(url);
      assert(responseCameFromRecording(response) == true);

      // replay cassette with custom expiration rules, should not find a match because recording is expired (throw exception)
      AdvancedSettings advancedSettings = AdvancedSettings(
          validTimeFrame: TimeFrame.never,
          whenExpired: ExpirationAction
              .throwException // throw exception when in replay mode
          );
      await Future.delayed(Duration(
          milliseconds:
              1000)); // Allow 1 second to lapse to ensure recording is now "expired"
      client = EasyVCRClient(cassette, Mode.replay,
          advancedSettings: advancedSettings);
      expect(client.post(url), throwsException);

      // replay cassette with bad expiration rules, should throw an exception because settings are bad
      advancedSettings = AdvancedSettings(
          validTimeFrame: TimeFrame.never,
          whenExpired: ExpirationAction
              .recordAgain // invalid settings for replay mode, should throw exception
          );
      client = EasyVCRClient(cassette, Mode.replay,
          advancedSettings: advancedSettings);
    });

    test('Ignore elements fail match test', () async {
      Cassette cassette =
          TestUtils.getCassette("test_ignore_elements_fail_match");
      cassette.erase(); // Erase cassette before recording

      Uri url = Uri.parse("https://google.com");
      String body1 =
          "{\"name\": \"Jack Sparrow\",\n    \"company\": \"EasyPost\"}";
      String body2 =
          "{\"name\": \"Different Name\",\n    \"company\": \"EasyPost\"}";

      // record baseline request first
      EasyVCRClient client = EasyVCRClient(cassette, Mode.record);
      await client.post(url, body: body1);

      // try to replay the request with different body data
      client = EasyVCRClient(cassette, Mode.replay,
          advancedSettings: AdvancedSettings(
              matchRules: MatchRules().byBody().byMethod().byFullUrl()));

      // should fail since we're strictly in replay mode and there's no exact match
      expect(client.post(url, body: body2), throwsException);
    });

    test('Ignore element pass match test', () async {
      Cassette cassette =
          TestUtils.getCassette("test_ignore_elements_pass_match");
      cassette.erase(); // Erase cassette before recording

      Uri url = Uri.parse("https://google.com");
      String body1 =
          "{\"name\": \"Jack Sparrow\",\n    \"company\": \"EasyPost\"}";
      String body2 =
          "{\"name\": \"Different Name\",\n    \"company\": \"EasyPost\"}";

      // record baseline request first
      EasyVCRClient client = EasyVCRClient(cassette, Mode.record);
      await client.post(url, body: body1);

      List<CensorElement> ignoreElements = [
        CensorElement("name", caseSensitive: false)
      ];

      // try to replay the request with different body data, but ignoring the differences
      client = EasyVCRClient(cassette, Mode.replay,
          advancedSettings: AdvancedSettings(
              matchRules: MatchRules()
                  .byBody(ignoreElements: ignoreElements)
                  .byMethod()
                  .byFullUrl()));

      // should succeed since we're ignoring the differences
      http.Response response = await client.post(url, body: body2);
      assert(responseCameFromRecording(response) == true);
    });

    test('Match settings test', () async {
      Cassette cassette = TestUtils.getCassette("test_match_settings");
      cassette.erase(); // Erase cassette before recording

      Uri url = Uri.parse("https://google.com");

      // record cassette first
      EasyVCRClient client = EasyVCRClient(cassette, Mode.record);
      await client.post(url);

      // replay cassette with default match rules, should find a match
      client = EasyVCRClient(cassette, Mode.replay);
      // add custom header to request, shouldn't matter when matching by default rules
      // shouldn't throw an exception
      await client.post(url, headers: {"X-Custom-Header": "custom-value"});

      // replay cassette with custom match rules, should not find a match because request is different (throw exception)
      AdvancedSettings advancedSettings =
          AdvancedSettings(matchRules: MatchRules().byEverything());
      client = EasyVCRClient(cassette, Mode.replay,
          advancedSettings: advancedSettings);
      // add custom header to request, causing a match failure when matching by everything
      expect(client.post(url, headers: {"X-Custom-Header": "custom-value"}),
          throwsException);
    });

    test('Nested censoring test', () async {
      Cassette cassette = TestUtils.getCassette("test_nested_censoring");
      cassette.erase(); // Erase cassette before recording

      Uri url = Uri.parse("https://google.com");
      String body =
          "{\r\n  \"array\": [\r\n    \"array_1\",\r\n    \"array_2\",\r\n    \"array_3\"\r\n  ],\r\n  \"dict\": {\r\n    \"nested_array\": [\r\n      \"nested_array_1\",\r\n      \"nested_array_2\",\r\n      \"nested_array_3\"\r\n    ],\r\n    \"nested_dict\": {\r\n      \"nested_dict_1\": {\r\n        \"nested_dict_1_1\": {\r\n          \"nested_dict_1_1_1\": \"nested_dict_1_1_1_value\"\r\n        }\r\n      },\r\n      \"nested_dict_2\": {\r\n        \"nested_dict_2_1\": \"nested_dict_2_1_value\",\r\n        \"nested_dict_2_2\": \"nested_dict_2_2_value\"\r\n      }\r\n    },\r\n    \"dict_1\": \"dict_1_value\",\r\n    \"null_key\": null\r\n  }\r\n}";

      // set up advanced settings
      const String censorString = "censored-by-test";
      Censors censors = Censors(censorString: censorString);
      censors.censorBodyElementsByKeys(
          ["nested_dict_1_1_1", "nested_dict_2_2", "nested_array", "null_key"]);
      AdvancedSettings advancedSettings = AdvancedSettings(censors: censors);

      // record cassette
      EasyVCRClient client = EasyVCRClient(cassette, Mode.record,
          advancedSettings: advancedSettings);
      await client.post(url, body: body);

      // NOTE: Have to manually check the cassette
    });

    test('Strict request matching test', () async {
      Cassette cassette = TestUtils.getCassette("test_strict_request_matching");
      cassette.erase(); // Erase cassette before recording

      Uri url = Uri.parse("https://google.com");
      String body =
          "{\n  \"address\": {\n    \"name\": \"Jack Sparrow\",\n    \"company\": \"EasyPost\",\n    \"street1\": \"388 Townsend St\",\n    \"street2\": \"Apt 20\",\n    \"city\": \"San Francisco\",\n    \"state\": \"CA\",\n    \"zip\": \"94107\",\n    \"country\": \"US\",\n    \"phone\": \"5555555555\"\n  }\n}";

      // record cassette first
      EasyVCRClient client = EasyVCRClient(cassette, Mode.record);
      http.Response response = await client.post(url, body: body);
      // check that the request body was not matched (should be a live call)
      assert(responseCameFromRecording(response) == false);

      // replay cassette with default match rules, should find a match
      client = EasyVCRClient(cassette, Mode.replay);

      // replay cassette
      client = EasyVCRClient(cassette, Mode.replay,
          advancedSettings:
              AdvancedSettings(matchRules: MatchRules.defaultStrictMatchRules));
      response = await client.post(url, body: body);

      // check that the request body was matched
      assert(responseCameFromRecording(response) == true);
    });
  });

  group('VCR tests', () {
    setUp(() {
      // Additional setup goes here.
    });

    test('Advanced settings test', () async {
      String censorString = "censored-by-test";
      AdvancedSettings advancedSettings = AdvancedSettings(
          censors: Censors(censorString: censorString).censorHeaderElementsByKeys(
            ["date"]
          )
      );
      VCR vcr = VCR(advancedSettings: advancedSettings);

      // test that the advanced settings are applied inside the VCR
      assert(vcr.advancedSettings == advancedSettings);

      // test that the advanced settings are passed to the cassette by checking if censor is applied
      Cassette cassette = TestUtils.getCassette("test_vcr_advanced_settings");
      vcr.insert(cassette);
      vcr.erase(); // Erase cassette before recording

      // record cassette first
      vcr.record();
      EasyVCRClient client = vcr.client;
      FakeDataService service = FakeDataService("json", client: client);
      await service.getIPAddressDataRawResponse();

      // now replay and confirm that the censor is applied
      vcr.replay();
      // changing the VCR settings won't affect a client after it's been grabbed from the VCR
      // so, we need to re-grab the VCR client and re-create the FakeDataService
      client = vcr.client;
      service = FakeDataService("json", client: client);
      http.StreamedResponse response = await service.getIPAddressDataRawResponse();
      Map<String, String> headers = response.headers;
      assert(headers.containsKey("date"));
      assert(headers["date"] == censorString);
    });

    test("Cassette name test", () async {
      String cassetteName = "test_vcr_cassette_name";
      Cassette cassette = TestUtils.getCassette(cassetteName);
      VCR vcr = TestUtils.getSimpleVCR(Mode.bypass);
      vcr.insert(cassette);

      // make sure the cassette name is set correctly
      assert(vcr.cassetteName == cassetteName);
    });

    test("Cassette swap test", () async {
      String cassette1Name = "test_vcr_cassette_swap_1";
      String cassette2Name = "test_vcr_cassette_swap_2";

      Cassette cassette1 = TestUtils.getCassette(cassette1Name);
      Cassette cassette2 = TestUtils.getCassette(cassette2Name);

      VCR vcr = TestUtils.getSimpleVCR(Mode.bypass);
      vcr.insert(cassette1);
      assert(vcr.cassetteName == cassette1Name);

      vcr.eject();
      assert(vcr.cassetteName == null);

      vcr.insert(cassette2);
      assert(vcr.cassetteName == cassette2Name);
    });

    test("VCR client test", () async {
      Cassette cassette = TestUtils.getCassette("test_vcr_client");
      VCR vcr = TestUtils.getSimpleVCR(Mode.bypass);
      vcr.insert(cassette);

      // make sure the VCR client is set correctly
      // no exception thrown when retrieving the client
      EasyVCRClient client = vcr.client;
    });


  });
}
