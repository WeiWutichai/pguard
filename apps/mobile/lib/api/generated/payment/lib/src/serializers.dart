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
import 'package:pguard_payment_api/src/model/deduction_batch.dart';
import 'package:pguard_payment_api/src/model/deduction_batch_detail.dart';
import 'package:pguard_payment_api/src/model/deduction_batch_item.dart';
import 'package:pguard_payment_api/src/model/deduction_batch_list.dart';
import 'package:pguard_payment_api/src/model/deduction_preview.dart';
import 'package:pguard_payment_api/src/model/error_body.dart';
import 'package:pguard_payment_api/src/model/error_detail.dart';
import 'package:pguard_payment_api/src/model/excluded_customer.dart';
import 'package:pguard_payment_api/src/model/excluded_guard.dart';
import 'package:pguard_payment_api/src/model/excluded_job.dart';
import 'package:pguard_payment_api/src/model/export_deduction_request.dart';
import 'package:pguard_payment_api/src/model/export_payout_request.dart';
import 'package:pguard_payment_api/src/model/export_refund_request.dart';
import 'package:pguard_payment_api/src/model/get_deduction_batch200_response.dart';
import 'package:pguard_payment_api/src/model/get_payout_batch200_response.dart';
import 'package:pguard_payment_api/src/model/get_payout_config200_response.dart';
import 'package:pguard_payment_api/src/model/get_prompt_pay200_response.dart';
import 'package:pguard_payment_api/src/model/get_refund_batch200_response.dart';
import 'package:pguard_payment_api/src/model/guard_earning.dart';
import 'package:pguard_payment_api/src/model/internal_export_user200_response.dart';
import 'package:pguard_payment_api/src/model/list_deduction_batches200_response.dart';
import 'package:pguard_payment_api/src/model/list_guard_earnings200_response.dart';
import 'package:pguard_payment_api/src/model/list_payments200_response.dart';
import 'package:pguard_payment_api/src/model/list_payout_batches200_response.dart';
import 'package:pguard_payment_api/src/model/list_refund_batches200_response.dart';
import 'package:pguard_payment_api/src/model/pay_with_slip200_response.dart';
import 'package:pguard_payment_api/src/model/payment.dart';
import 'package:pguard_payment_api/src/model/payment_status.dart';
import 'package:pguard_payment_api/src/model/payout_batch.dart';
import 'package:pguard_payment_api/src/model/payout_batch_detail.dart';
import 'package:pguard_payment_api/src/model/payout_batch_item.dart';
import 'package:pguard_payment_api/src/model/payout_batch_list.dart';
import 'package:pguard_payment_api/src/model/payout_config.dart';
import 'package:pguard_payment_api/src/model/payout_preview.dart';
import 'package:pguard_payment_api/src/model/preview_cut_job.dart';
import 'package:pguard_payment_api/src/model/preview_deductions200_response.dart';
import 'package:pguard_payment_api/src/model/preview_payout200_response.dart';
import 'package:pguard_payment_api/src/model/preview_recipient.dart';
import 'package:pguard_payment_api/src/model/preview_refund_recipient.dart';
import 'package:pguard_payment_api/src/model/preview_refunds200_response.dart';
import 'package:pguard_payment_api/src/model/prompt_pay_info.dart';
import 'package:pguard_payment_api/src/model/refund_batch.dart';
import 'package:pguard_payment_api/src/model/refund_batch_detail.dart';
import 'package:pguard_payment_api/src/model/refund_batch_item.dart';
import 'package:pguard_payment_api/src/model/refund_batch_list.dart';
import 'package:pguard_payment_api/src/model/refund_preview.dart';
import 'package:pguard_payment_api/src/model/refund_queue_item.dart';
import 'package:pguard_payment_api/src/model/refund_queue_response.dart';
import 'package:pguard_payment_api/src/model/refund_source_kind.dart';
import 'package:pguard_payment_api/src/model/refund_source_ref.dart';
import 'package:pguard_payment_api/src/model/refund_status.dart';
import 'package:pguard_payment_api/src/model/revenue_point.dart';
import 'package:pguard_payment_api/src/model/revenue_report.dart';
import 'package:pguard_payment_api/src/model/set_deduction_batch_status200_response.dart';
import 'package:pguard_payment_api/src/model/set_deduction_batch_status_request.dart';
import 'package:pguard_payment_api/src/model/set_payout_batch_status200_response.dart';
import 'package:pguard_payment_api/src/model/set_payout_batch_status_request.dart';
import 'package:pguard_payment_api/src/model/set_refund_batch_status200_response.dart';
import 'package:pguard_payment_api/src/model/set_refund_batch_status_request.dart';
import 'package:pguard_payment_api/src/model/update_payout_config_request.dart';
import 'package:pguard_payment_api/src/model/vat_register_report.dart';
import 'package:pguard_payment_api/src/model/vat_register_report200_response.dart';
import 'package:pguard_payment_api/src/model/vat_register_row.dart';
import 'package:pguard_payment_api/src/model/void_deduction_batch_items_request.dart';
import 'package:pguard_payment_api/src/model/void_deduction_batch_request.dart';
import 'package:pguard_payment_api/src/model/void_payout_batch_items_request.dart';
import 'package:pguard_payment_api/src/model/void_payout_batch_request.dart';
import 'package:pguard_payment_api/src/model/void_refund_batch_items_request.dart';
import 'package:pguard_payment_api/src/model/void_refund_batch_request.dart';
import 'package:pguard_payment_api/src/model/wht_payee_report.dart';
import 'package:pguard_payment_api/src/model/wht_payee_report200_response.dart';
import 'package:pguard_payment_api/src/model/wht_payee_row.dart';

part 'serializers.g.dart';

@SerializersFor([
  AdminCustomerSpendReport200Response,
  AdminRefundQueue200Response,
  AdminRevenueReport200Response,
  ApiResponseEnvelope,$ApiResponseEnvelope,
  CreatePaymentRequest,
  CustomerSpend,
  DeductionBatch,$DeductionBatch,
  DeductionBatchDetail,
  DeductionBatchItem,
  DeductionBatchList,
  DeductionPreview,
  ErrorBody,
  ErrorDetail,
  ExcludedCustomer,
  ExcludedGuard,
  ExcludedJob,
  ExportDeductionRequest,
  ExportPayoutRequest,
  ExportRefundRequest,
  GetDeductionBatch200Response,
  GetPayoutBatch200Response,
  GetPayoutConfig200Response,
  GetPromptPay200Response,
  GetRefundBatch200Response,
  GuardEarning,
  InternalExportUser200Response,
  ListDeductionBatches200Response,
  ListGuardEarnings200Response,
  ListPayments200Response,
  ListPayoutBatches200Response,
  ListRefundBatches200Response,
  PayWithSlip200Response,
  Payment,
  PaymentStatus,
  PayoutBatch,$PayoutBatch,
  PayoutBatchDetail,
  PayoutBatchItem,
  PayoutBatchList,
  PayoutConfig,
  PayoutPreview,
  PreviewCutJob,
  PreviewDeductions200Response,
  PreviewPayout200Response,
  PreviewRecipient,
  PreviewRefundRecipient,
  PreviewRefunds200Response,
  PromptPayInfo,
  RefundBatch,$RefundBatch,
  RefundBatchDetail,
  RefundBatchItem,
  RefundBatchList,
  RefundPreview,
  RefundQueueItem,
  RefundQueueResponse,
  RefundSourceKind,
  RefundSourceRef,
  RefundStatus,
  RevenuePoint,
  RevenueReport,
  SetDeductionBatchStatus200Response,
  SetDeductionBatchStatusRequest,
  SetPayoutBatchStatus200Response,
  SetPayoutBatchStatusRequest,
  SetRefundBatchStatus200Response,
  SetRefundBatchStatusRequest,
  UpdatePayoutConfigRequest,
  VatRegisterReport,
  VatRegisterReport200Response,
  VatRegisterRow,
  VoidDeductionBatchItemsRequest,
  VoidDeductionBatchRequest,
  VoidPayoutBatchItemsRequest,
  VoidPayoutBatchRequest,
  VoidRefundBatchItemsRequest,
  VoidRefundBatchRequest,
  WhtPayeeReport,
  WhtPayeeReport200Response,
  WhtPayeeRow,
])
Serializers serializers = (_$serializers.toBuilder()
      ..add(ApiResponseEnvelope.serializer)
      ..add(DeductionBatch.serializer)
      ..add(PayoutBatch.serializer)
      ..add(RefundBatch.serializer)
      ..add(const OneOfSerializer())
      ..add(const AnyOfSerializer())
      ..add(const DateSerializer())
      ..add(Iso8601DateTimeSerializer())
    ).build();

Serializers standardSerializers =
    (serializers.toBuilder()..addPlugin(StandardJsonPlugin())).build();
