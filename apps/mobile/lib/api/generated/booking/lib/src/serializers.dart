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
import 'package:pguard_booking_api/src/date_serializer.dart';
import 'package:pguard_booking_api/src/model/date.dart';

import 'package:pguard_booking_api/src/model/admin_bookings_report200_response.dart';
import 'package:pguard_booking_api/src/model/admin_customer_bookings_report200_response.dart';
import 'package:pguard_booking_api/src/model/admin_list_services200_response.dart';
import 'package:pguard_booking_api/src/model/api_response_envelope.dart';
import 'package:pguard_booking_api/src/model/assign_guard_request.dart';
import 'package:pguard_booking_api/src/model/available_guard.dart';
import 'package:pguard_booking_api/src/model/booking.dart';
import 'package:pguard_booking_api/src/model/booking_status.dart';
import 'package:pguard_booking_api/src/model/bookings_report.dart';
import 'package:pguard_booking_api/src/model/create_booking_request.dart';
import 'package:pguard_booking_api/src/model/create_progress_report200_response.dart';
import 'package:pguard_booking_api/src/model/create_service_request.dart';
import 'package:pguard_booking_api/src/model/customer_booking_stat.dart';
import 'package:pguard_booking_api/src/model/daily_count.dart';
import 'package:pguard_booking_api/src/model/error_body.dart';
import 'package:pguard_booking_api/src/model/error_detail.dart';
import 'package:pguard_booking_api/src/model/get_internal_booking200_response.dart';
import 'package:pguard_booking_api/src/model/inline_object.dart';
import 'package:pguard_booking_api/src/model/inline_object1.dart';
import 'package:pguard_booking_api/src/model/internal_booking.dart';
import 'package:pguard_booking_api/src/model/internal_export_user200_response.dart';
import 'package:pguard_booking_api/src/model/list_available_guards200_response.dart';
import 'package:pguard_booking_api/src/model/list_bookings200_response.dart';
import 'package:pguard_booking_api/src/model/list_progress_reports200_response.dart';
import 'package:pguard_booking_api/src/model/progress_report.dart';
import 'package:pguard_booking_api/src/model/retention_point.dart';
import 'package:pguard_booking_api/src/model/review_completion_request.dart';
import 'package:pguard_booking_api/src/model/service_catalog_item.dart';
import 'package:pguard_booking_api/src/model/update_service_request.dart';
import 'package:pguard_booking_api/src/model/utilization_cell.dart';

part 'serializers.g.dart';

@SerializersFor([
  AdminBookingsReport200Response,
  AdminCustomerBookingsReport200Response,
  AdminListServices200Response,
  ApiResponseEnvelope,$ApiResponseEnvelope,
  AssignGuardRequest,
  AvailableGuard,
  Booking,
  BookingStatus,
  BookingsReport,
  CreateBookingRequest,
  CreateProgressReport200Response,
  CreateServiceRequest,
  CustomerBookingStat,
  DailyCount,
  ErrorBody,
  ErrorDetail,
  GetInternalBooking200Response,
  InlineObject,
  InlineObject1,
  InternalBooking,
  InternalExportUser200Response,
  ListAvailableGuards200Response,
  ListBookings200Response,
  ListProgressReports200Response,
  ProgressReport,
  RetentionPoint,
  ReviewCompletionRequest,
  ServiceCatalogItem,
  UpdateServiceRequest,
  UtilizationCell,
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
