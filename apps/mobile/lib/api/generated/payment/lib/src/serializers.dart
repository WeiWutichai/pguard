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
import 'package:pguard_payment_api/src/date_serializer.dart';
import 'package:pguard_payment_api/src/model/date.dart';

import 'package:pguard_payment_api/src/model/admin_customer_spend_report200_response.dart';
import 'package:pguard_payment_api/src/model/admin_refund_queue200_response.dart';
import 'package:pguard_payment_api/src/model/admin_revenue_report200_response.dart';
import 'package:pguard_payment_api/src/model/api_response_envelope.dart';
import 'package:pguard_payment_api/src/model/create_payment_request.dart';
import 'package:pguard_payment_api/src/model/customer_spend.dart';
import 'package:pguard_payment_api/src/model/error_body.dart';
import 'package:pguard_payment_api/src/model/error_detail.dart';
import 'package:pguard_payment_api/src/model/get_prompt_pay200_response.dart';
import 'package:pguard_payment_api/src/model/internal_export_user200_response.dart';
import 'package:pguard_payment_api/src/model/list_payments200_response.dart';
import 'package:pguard_payment_api/src/model/pay_with_slip200_response.dart';
import 'package:pguard_payment_api/src/model/payment.dart';
import 'package:pguard_payment_api/src/model/payment_status.dart';
import 'package:pguard_payment_api/src/model/prompt_pay_info.dart';
import 'package:pguard_payment_api/src/model/refund_queue_item.dart';
import 'package:pguard_payment_api/src/model/refund_queue_response.dart';
import 'package:pguard_payment_api/src/model/refund_status.dart';
import 'package:pguard_payment_api/src/model/revenue_point.dart';
import 'package:pguard_payment_api/src/model/revenue_report.dart';

part 'serializers.g.dart';

@SerializersFor([
  AdminCustomerSpendReport200Response,
  AdminRefundQueue200Response,
  AdminRevenueReport200Response,
  ApiResponseEnvelope,$ApiResponseEnvelope,
  CreatePaymentRequest,
  CustomerSpend,
  ErrorBody,
  ErrorDetail,
  GetPromptPay200Response,
  InternalExportUser200Response,
  ListPayments200Response,
  PayWithSlip200Response,
  Payment,
  PaymentStatus,
  PromptPayInfo,
  RefundQueueItem,
  RefundQueueResponse,
  RefundStatus,
  RevenuePoint,
  RevenueReport,
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
