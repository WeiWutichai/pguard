//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_import

import 'package:one_of_serializer/any_of_serializer.dart';
import 'package:one_of_serializer/one_of_serializer.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/serializer.dart';
import 'package:built_value/standard_json_plugin.dart';
import 'package:built_value/iso_8601_date_time_serializer.dart';
import 'package:pguard_rating_api/src/date_serializer.dart';
import 'package:pguard_rating_api/src/model/date.dart';

import 'package:pguard_rating_api/src/model/admin_review.dart';
import 'package:pguard_rating_api/src/model/admin_review_stats.dart';
import 'package:pguard_rating_api/src/model/admin_reviews.dart';
import 'package:pguard_rating_api/src/model/api_response_envelope.dart';
import 'package:pguard_rating_api/src/model/batch_internal_rating_summaries200_response.dart';
import 'package:pguard_rating_api/src/model/batch_rating_summaries_request.dart';
import 'package:pguard_rating_api/src/model/create_review_request.dart';
import 'package:pguard_rating_api/src/model/error_body.dart';
import 'package:pguard_rating_api/src/model/error_detail.dart';
import 'package:pguard_rating_api/src/model/get_guard_ratings200_response.dart';
import 'package:pguard_rating_api/src/model/get_internal_rating_summary200_response.dart';
import 'package:pguard_rating_api/src/model/get_own_review200_response.dart';
import 'package:pguard_rating_api/src/model/guard_ratings.dart';
import 'package:pguard_rating_api/src/model/internal_export_user200_response.dart';
import 'package:pguard_rating_api/src/model/list_admin_reviews200_response.dart';
import 'package:pguard_rating_api/src/model/rating_summary.dart';
import 'package:pguard_rating_api/src/model/rating_summary_batch_item.dart';
import 'package:pguard_rating_api/src/model/review.dart';
import 'package:pguard_rating_api/src/model/set_review_visibility200_response.dart';
import 'package:pguard_rating_api/src/model/set_review_visibility200_response_all_of_data.dart';
import 'package:pguard_rating_api/src/model/set_review_visibility_request.dart';
import 'package:pguard_rating_api/src/model/submit_review200_response.dart';
import 'package:pguard_rating_api/src/model/submit_review200_response_all_of_data.dart';

part 'serializers.g.dart';

@SerializersFor([
  AdminReview,
  AdminReviewStats,
  AdminReviews,
  ApiResponseEnvelope,$ApiResponseEnvelope,
  BatchInternalRatingSummaries200Response,
  BatchRatingSummariesRequest,
  CreateReviewRequest,
  ErrorBody,
  ErrorDetail,
  GetGuardRatings200Response,
  GetInternalRatingSummary200Response,
  GetOwnReview200Response,
  GuardRatings,
  InternalExportUser200Response,
  ListAdminReviews200Response,
  RatingSummary,
  RatingSummaryBatchItem,
  Review,
  SetReviewVisibility200Response,
  SetReviewVisibility200ResponseAllOfData,
  SetReviewVisibilityRequest,
  SubmitReview200Response,
  SubmitReview200ResponseAllOfData,
])
Serializers serializers = (_$serializers.toBuilder()
      ..add(ApiResponseEnvelope.serializer)
      ..add(const OneOfSerializer())
      ..add(const AnyOfSerializer())
      ..add(const DateSerializer())
      ..add(Iso8601DateTimeSerializer())
    ).build();

Serializers standardSerializers =
    (serializers.toBuilder()..addPlugin(StandardJsonPlugin())).build();
