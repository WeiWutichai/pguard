# CPX Toolkit (SCB Business Net Excel Toolkit) — Full Reverse‑Engineering Reference

> Source: `CPX_Toolkit_Template.xlsm` · **Toolkit Version 1.3.8** · macro‑enabled (`vbaProject.bin`, 12 VBA modules).
> Purpose: a Thai (Siam Commercial Bank) corporate template that turns the **Payment / Invoice / WHT** sheets into a
> **pipe‑delimited (`|`) text file** for bulk upload to SCB Business Net (bulk transfer / payroll + e‑Invoice + e‑Withholding‑Tax).
> This document is produced by decompiling the VBA (custom OLE2 + MS‑OVBA decompressor) and parsing the sheet XML.

---

## 1. Executive summary — how the upload file is built

Pressing **Export** (button on the *Payment* sheet → `Export.Export()`) does:

1. **Validate** the whole workbook (`retry` re‑runs every cell validator); if the error‑count cell `Payment!N1 > 0` → abort with `EXPORT_ERROR`.
2. **Auto‑generate** the batch reference if empty (`Format(Now(),"DDMMYYHHMMSS")`) and derive the file reference.
3. Guard rules: credit Seq‑No must not be blank; for **Payroll** products, Invoice/WHT are force‑disabled (not supported); `validateInvoiceAndWHT()` cross‑checks the Invoice/WHT checkboxes against whether those sheets actually contain rows.
4. Prompt *"Do you want to generate text file for upload?"* → `GetSaveAsFilename` (`.txt`).
5. **Assemble** the text and write it as **UTF‑8 _without_ BOM** (ADODB.Stream writes UTF‑8, then a binary re‑save from `position = 3` strips the 3‑byte BOM).

## 2. Canonical file format

Pipe‑delimited, one record per line, records **nested per recipient**:

```
HEADER | customerFileRef | systemReferenceId
BCHDET | batchRef | productCode | valueDate(YYYYMMDD) | debitAcc | feeDebitAcc | totalAmount | creditCount |  |
TXNDET | …28 fields…                         ← recipient #1
   INVDET | …10 fields…                       ← invoice(s) for recipient #1   (only if Invoice checkbox on)
   WHTCER | …19 + up to 5×7 detail fields…    ← WHT cert(s) for recipient #1  (only if WHT checkbox on)
TXNDET | …                                    ← recipient #2
   …
TRAILR | 1 | creditCount | totalAmount
```

The `TXNDET`, and its nested `INVDET`/`WHTCER`, are matched by **Credit Seq‑No** (`Payment!A`), looped one recipient at a time in `Sheet1.ExportDataCredit()`.

### Record types

| Code | Record | Fields | Built by |
|---|---|---|---|
| `HEADER` | File header | 3 | `Export.Export` |
| `BCHDET` | Batch / debit (one) | 10 | `Sheet1.ExportDebitRow` |
| `TXNDET` | Credit / transaction (per recipient) | 28 | `Sheet1.ExportCreditRow` |
| `INVDET` | Invoice detail (nested) | 10 | `Sheet3.ExportInvoiceRow` |
| `WHTCER` | WHT certificate (nested) | 19 + 5×7 | `Sheet4.ExportWHTRow` |
| `TRAILR` | Trailer (counts + total) | 4 | `Export.CountTotalRecord` |

## 3. Formatting rules (shared)

| Rule | Function | Behaviour |
|---|---|---|
| Delimiter | const `delim` | `"\|"` |
| Amount | `convertAmountFormat` | `FormatNumber(x,2)` then strip commas → `1234.56` (2 decimals, no thousands sep) |
| Date | `convertDateFormat` → `convDate`/`calYear` | → `YYYYMMDD`, year normalised between พ.ศ. (Buddhist) and ค.ศ. (Gregorian) |
| Phone | `removeDashSignPhoneNum` | strips `-` |
| Flags (SMS/Email/WHT/Invoice) | `checkFlagHaveValue` / `checkRequiredFlag` | `Y`/`N` (or count/amount when required) |
| Encoding | ADODB.Stream | **UTF‑8 without BOM** |
| File name | `generateCustomerFileReferanceName` | `SCB_file_reference_<first 12 chars of batchRef+productCode>` |

## 4. Module map (12 VBA modules)

| Module | Sheet / role | Lines | What it owns |
|---|---|---|---|
| `Sheet1` | **Payment** | 1444 | Header+credit grid, dropdown cascades, `BCHDET`+`TXNDET` builders, per‑row validation dispatch |
| `Sheet4` | **WHT** | 1007 | `WHTCER` builder (19 header + up to 5 income‑detail blocks), WHT column schema |
| `Validation` | (module) | 1316 | **Master constants** (codes, cell addresses, `idxHeader`), the error‑code catalogue, every validator |
| `Util` | (module) | 625 | Format helpers (`convertAmountFormat`/`convertDateFormat`/`calYear`), Master_data lookups, flag helpers |
| `Sheet3` | **Invoice** | 381 | `INVDET` builder, invoice column schema |
| `Export` | (module) | 295 | Top‑level `Export()` flow, `HEADER`/`TRAILR`, UTF‑8‑no‑BOM write |
| `Clear` | (module) | 152 | Reset/clear per sheet |
| `ThisWorkbook` | (workbook) | 74 | Workbook open/close events, init |
| `Sheet5/6/8` | Master_data / File_Info / other | 8 ea. | Stubs |
| `UserForm1` | form | 0 | Empty designer stub |

## 5. Product codes (drive the `TXNDET` branching)

`PAY/PA2/PA3` = SCB Payroll 1/2/3 · `SPN/SPS(+2/3)` = Payroll SMART Credit next/same‑day · `OAT` = own‑account · `3PT` = 3rd‑party · `BNT` = BAHTNET · `RFT` = other‑bank (ORFT) · `PPY` = PromptPay. Field 3 (proxy), 4 (bank/clearing), 5 (branch) and 7 (service type) are set per product — see the *Sheet1* section §7.2.

---

> The sections below are the exhaustive per‑module decompilation. Order: **Sheet data & lookups → Validation/schema → Export flow (Invoice/Export/Clear) → Payment (Sheet1) → WHT (Sheet4) → Util & Workbook.**



---

## Workbook Structure Reference — `CPX_Toolkit_Template.xlsm` (SCB Business Net Toolkit v1.3.8)

*Extracted directly from the OOXML parts (`xl/worksheets/*.xml`, `xl/tables/*.xml`, `xl/sharedStrings.xml`, `xl/workbook.xml`, `xl/drawings/*`) using stdlib `zipfile` + `xml.etree` only. Every value below is the actual stored content, not a sample.*

### 1. Sheet inventory & VBA code-name map

| Tab order | Sheet name (as displayed) | File | `sheetId` | State | VBA code name (per context) | Purpose |
|---|---|---|---|---|---|---|
| 1 | `วิธีการเปิดใช้งาน Excel Toolkit` (How to enable the Toolkit) | `xl/worksheets/sheet1.xml` | 12 | visible | — (Instructions) | Usage instructions — **image only, no cell text** |
| 2 | `Payment` | `xl/worksheets/sheet2.xml` | 4 | visible | **Sheet1** | Config block + credit (recipient) table — the user-facing entry sheet |
| 3 | `Invoice` | `xl/worksheets/sheet3.xml` | 3 | **hidden** | **Sheet3** | Per-recipient e-Invoice detail (INVDET source) |
| 4 | `WHT` | `xl/worksheets/sheet4.xml` | 2 | **hidden** | **Sheet4** | Per-recipient withholding-tax detail (WHTCER source) |
| 5 | `Master_data` | `xl/worksheets/sheet5.xml` | 10 | **hidden** | **Sheet5** | All lookup/code tables (23 Excel Tables + error strings) |
| 6 | `File_Info` | `xl/worksheets/sheet6.xml` | 7 | visible | **Sheet6/8** | Version + changelog |

Note the tab order does **not** match `sheetId`; the VBA code name "Sheet1" is the **Payment** sheet (a classic source of confusion for re-implementers). The `r:id`→file map is `rId1→sheet1 … rId6→sheet6` (confirmed in `xl/_rels/workbook.xml.rels`).

---

### 2. `Master_data` sheet — all lookup tables (source of every code↔label map)

Master_data uses **only columns A (label) and B (code)**, rows 1–364. It is carved into **23 Excel Tables** (defined in `xl/tables/table*.xml`), each a contiguous `A..:B..` range with a 2-cell header row. Every table below is dumped in full.

#### 2.1 `TBProductCode` — Product ↔ Product Code (range `A1:B17`)
This is the master product list. The 3-letter code is what lands in the file's `productCode` field (BCHDET) and is embedded in the auto-generated Customer File Ref.

| Product | Product Code |
|---|---|
| SCB Payroll1 | `PAY` |
| SCB Payroll2 | `PA2` |
| SCB Payroll3 | `PA3` |
| SCB Payroll1 - SMART Credit (Next Day) | `SPN` |
| SCB Payroll1 - SMART Credit (Same Day) | `SPS` |
| SCB Payroll2 - SMART Credit (Next Day) | `SPN2` |
| SCB Payroll2 - SMART Credit (Same Day) | `SPS2` |
| SCB Payroll3 - SMART Credit (Next Day) | `SPN3` |
| SCB Payroll3 - SMART Credit (Same Day) | `SPS3` |
| Own account transfer | `OAT` |
| 3rd Party Transfer | `3PT` |
| SCB BAHTNET | `BNT` |
| Other Bank Transfer (ORFT) | `RFT` |
| SCB SMART Credit (Next Day) | `SCN` |
| SCB SMART Credit (SameDay) | `SCS` |
| PromptPay Payment | `PPY` |

#### 2.2 `TBPromptPayPoxcy` — PromptPay proxy type (range `A19:B23`)
*(Table name is misspelled "Poxcy"; header cell says "PromptPay Poxy" — both typos of "Proxy".)*

| PromptPay Proxy | Code |
|---|---|
| Tax ID | `AX` |
| National ID | `NAT` |
| Mobile No | `MOB` |
| E-Wallet (for PromptPay Realtime only) | `EWL` |

#### 2.3 `TBWHTType` — WHT form type ภงด. (range `A25:B32`)
Feeds the WHT sheet **column O** dropdown; the resolved code goes to WHT header helper **column P** (`WHT Form Type Code`).

| WHT Type (แบบ) | Code |
|---|---|
| ภงด 1 ก | `01` |
| ภงด 2 | `03` |
| ภงด 3 | `04` |
| ภงด 1 ก พิเศษ | `11` |
| ภงด 2 ก | `12` |
| ภงด 3 ก | `13` |
| ภงด 53 | `53` |

*(Note the non-contiguous codes: 01, 03, 04, 11, 12, 13, 53 — do not assume sequential.)*

#### 2.4 `TBWHTPayType` — WHT pay type / who bears the tax (range `A34:B38`)
Feeds WHT **column R**; code → helper **column S** (`WHT Pay Type Code`). Code `4` ("อื่นๆ") requires free-text in column T.

| WHT Pay Type | Code |
|---|---|
| ผู้จ่ายออกครั้งเดียว (payer pays once) | `1` |
| ออกให้ตลอดไป (payer always pays) | `2` |
| หักภาษี ณ ที่จ่าย (withhold at source) | `3` |
| อื่นๆ (other) | `4` |

#### 2.5 `TBIncomeType` — WHT income type (range `A40:B55`)
Feeds WHT income-detail blocks (columns Y/AG/AO/AW/BE). **Label == Code** for every row.

| WHT Income Type | Code |
|---|---|
| 1 | `1` |
| 2 | `2` |
| 3 | `3` |
| 4a | `4a` |
| 4b1.1 | `4b1.1` |
| 4b1.2 | `4b1.2` |
| 4b1.3 | `4b1.3` |
| 4b1.4 | `4b1.4` |
| 4b2.1 | `4b2.1` |
| 4b2.2 | `4b2.2` |
| 4b2.3 | `4b2.3` |
| 4b2.4 | `4b2.4` |
| 4b2.5 | `4b2.5` |
| 5 | `5` |
| 6 | `6` |

*Business rule (from error strings): income type `4b1.4` requires "Percentage of Dividend to Net Profit" (col AB); max **3 unique** income types per transaction.*

#### 2.6 `TBServiceType` — transaction purpose / Service Type (range `A57:B81`)
Feeds credit-table **column I** (`Service Type`). 24 entries, codes `00`–`23`.

| Service Type | Code |
|---|---|
| Other | `00` |
| Freight | `01` |
| Insurance Premium | `02` |
| Transportation Cost | `03` |
| Travelling Expenses (Thai) | `04` |
| Foreign Tourist Expenses | `05` |
| Interest Paid | `06` |
| Dividened *(sic)* | `07` |
| Education | `08` |
| Royalty Fee | `09` |
| Agency Expenses | `10` |
| Advertising Fee | `11` |
| Communication Cost | `12` |
| Personal Remittance / Family Support | `13` |
| Money Transfer for Government | `14` |
| Embassy / Military / Government Expenses | `15` |
| Thai Lobour Money Transfer *(sic)* | `16` |
| Salary | `17` |
| Commission Fee | `18` |
| Loan | `19` |
| Direct Investment | `20` |
| Portfolio Investment | `21` |
| Trade Transaction | `22` |
| Fixed Asset Investment | `23` |

#### 2.7 `TBWHTDeliveryMethod` — WHT certificate delivery (range `A83:B85`)

| WHT Delivery Method | Code |
|---|---|
| send by email | `E` |
| Not send (but could download from CPX) | `N` |

#### 2.8 Bank tables (6 variants) — Bank THAI Name ↔ 3-digit Bank Code
There are **six** bank sub-lists. Which one populates the credit-table Bank-Code dropdown depends on the selected product. The **canonical/full list is `TBBank`** (38 banks). The variants are subsets — deltas computed exactly below.

##### `TBBank` — full list (range `A87:B125`, 38 rows)

| Bank Code | Bank THAI Name |
|---|---|
| `001` | ธนาคารแห่งประเทศไทย |
| `002` | กรุงเทพ |
| `004` | กสิกรไทย |
| `006` | กรุงไทย |
| `008` | เจพีมอร์แกน เชส |
| `009` | โอซีบีซี |
| `011` | ทหารไทยธนชาต จำกัด (มหาชน) |
| `014` | ไทยพาณิชย์ |
| `017` | ซิตี้แบงค์ |
| `018` | ซูมิโตโม มิตซุย แบงกิ้ง คอร์ปอเรชั่น |
| `020` | สแตนดาร์ดชาร์เตอร์ด (ไทย) |
| `022` | ซีไอเอ็มบี |
| `023` | อาร์ เอช บี จำกัด |
| `024` | ยูโอบี |
| `025` | กรุงศรีอยุธยา |
| `026` | เมกะ สากลพาณิชย์ จำกัด |
| `027` | แห่งอเมริกา เนชั่นแนล แอสโซซิเอชั่น |
| `029` | อินเดียน โอเวอร์ซีส์ |
| `030` | ออมสิน |
| `031` | ฮ่องกงและเซี่ยงไฮ้แบงกิ้งคอร์ปอเรชั่น จำกัด |
| `032` | ดอยซ์แบงค์ |
| `033` | อาคารสงเคราะห์ |
| `034` | เพื่อการเกษตรและสหกรณ์ |
| `035` | ธนาคารเพื่อการส่งออกและนำเข้าแห่งประเทศไทย |
| `039` | มิตซูโฮ คอร์ปอเรต จำกัด |
| `045` | บีเอ็นพี พารีบาส์ สาขากรุงเทพฯ |
| `052` | ธนาคารแห่งประเทศจีน (ไทย) |
| `065` | ธนชาต |
| `066` | อิสลามแห่งประเทศไทย |
| `067` | ทิสโก้ |
| `069` | เกียรตินาคิน |
| `070` | ไอซีบีซี (ไทย) |
| `071` | ไทยเครดิต เพื่อรายย่อย |
| `073` | แลนด์แอนด์เฮ้าส์ |
| `079` | เอเอ็นแซด (ไทย) |
| `080` | ซูมิโตโม มิตซุย ทรัสต์ (ไทย) |
| `088` | คลิกซ์ |
| `098` | ธนาคารพัฒนาวิสาหกิจขนาดกลางและขนาดย่อมแห่งประเทศไทย |

##### Bank-list variants (subsets of `TBBank` — same codes/names, only membership differs)

| Table | Range | Count | Difference vs `TBBank` | Used for |
|---|---|---|---|---|
| `TBBank` | `A87:B125` | 38 | (canonical) | general |
| `TBBankBNT1` | `A127:B164` | 37 | **omits `014` (SCB)** | BAHTNET recipient bank (can't BAHTNET to own bank) |
| `TBBankWithout014` | `A166:B203` | 37 | **omits `080`** — ⚠️ **misnomer: it still CONTAINS `014`** and instead drops `080` (Sumitomo Mitsui Trust) | ORFT/other |
| `TBBankSmartCredit` | `A205:B241` | 36 | **omits both `014` and `080`** | SMART Credit recipient bank |
| `TBBankPAY` | `A243:B244` | 1 | only `014` ไทยพาณิชย์ | SCB Payroll / own-account (SCB-only) |
| `TBBankPPY` | `A246:B247` | 1 | only `111` พร้อมเพย์ (PromptPay) | PromptPay product |

> ⚠️ **Re-implementer trap:** the table named `TBBankWithout014` does **not** exclude `014`; it excludes `080`. Do not trust the name — trust the range membership above.

#### 2.9 Product sub-group tables (drive the Product dropdown per radio button)
The Payment sheet's four radio buttons swap which of these lists populates the Product selector (cell `E4`).

**`TBPPPayroll`** (`A249:B258`) — radio "Payroll":

| Payroll | Code |
|---|---|
| SCB Payroll1 | `PAY` |
| SCB Payroll2 | `PA2` |
| SCB Payroll3 | `PA3` |
| SCB Payroll1 - SMART Credit (Next Day) | `SPN` |
| SCB Payroll1 - SMART Credit (Same Day) | `SPS` |
| SCB Payroll2 - SMART Credit (Next Day) | `SPN2` |
| SCB Payroll2 - SMART Credit (Same Day) | `SPS2` |
| SCB Payroll3 - SMART Credit (Next Day) | `SPN3` |
| SCB Payroll3 - SMART Credit (Same Day) | `SPS3` |

**`TBPPSCBTransfer`** (`A260:B262`) — radio "SCB Transfer": `Own account transfer`=`OAT`, `3rd Party Transfer`=`3PT`
**`TBPPOtherBankTransfer`** (`A264:B268`) — radio "Other Bank Transfer": `SCB BAHTNET`=`BNT`, `Other Bank Transfer (ORFT)`=`RFT`, `SCB SMART Credit (Next Day)`=`SCN`, `SCB SMART Credit (SameDay)`=`SCS`
**`TBPPPromptPay`** (`A270:B271`) — radio "PromptPay": `PromptPay Payment`=`PPY`

#### 2.10 Fee-charge tables — "Fee Charge" (credit-table column G)
Three variants by product family; code goes into the TXNDET fee field.

| Table | Range | Entries |
|---|---|---|
| `TBFeeBNT` (BAHTNET) | `A273:B275` | `Recipient (BEN)`=`BEN`, `Share (SHA)`=`SHA` |
| `TBFeePayroll` | `A277:B279` | `Recipient (BEN)`=`BEN`, `Payer (OUR)`=`OUR` |
| `TBFeeOther` | `A281:B283` | `Recipient (BEN)`=`BEN`, `Payer (OUR)`=`OUR` |

*Fee-charge code meanings (from the `G8` validation prompt): OUR = payer bears fee; BEN = recipient bears fee; SHA = shared. Note BAHTNET uses BEN/SHA (no OUR); the others use BEN/OUR (no SHA).*

#### 2.11 SMART service-type tables
| Table | Range | Entries |
|---|---|---|
| `TBServiceTypePayroll` | `A285:B286` | `Freight`=`01` (single row — SMART Payroll purpose) |
| `TBServiceTypeSmart` | `A288:B299` | see below |

`TBServiceTypeSmart` (SMART Credit purposes):

| Smart Service Type | Code |
|---|---|
| Salaries wages or pensions | `01` |
| Dividends | `02` |
| Interests | `03` |
| Goods and Services | `04` |
| Securities Trading | `05` |
| Tax Refunds | `06` |
| Loans | `07` |
| Senior Citizen Allowances | `08` |
| Government Bond | `09` |
| Government Welfare/Pensions | `10` |
| Others | `59` |

#### 2.12 `TBErrorMessage` — validation error catalog (range `A301:B364`, 63 rows)
Key ↔ message map used by the VBA validators. Full dump (`\n` = literal newline in the message):

| Key | Message |
|---|---|
| `PRODUCT` | Please select the information in this field. |
| `NUMBER` | The information in this field must be number. |
| `FIX_4_NUMBER` | The information in this field must be in number with 4 digits. |
| `AMOUNT` | The information in this field must be number. |
| `AMOUNT_DECIMAL` | Decimal number cannot more than 2 digit. |
| `EMAIL` | The information in this field must be email and not exceed 100 maximum length.\n\nNot allows special characters: \| |
| `PHONE_10` | The information in this field must be mobile number 10. |
| `PHONE` | The information in this field must be mobile number and not exceed 3 maximum mobile numbers. |
| `DATE` | Data format is not correct. |
| `SPECIAL_SPACE` | Not allows special characters: ! " #\n$ % & * +  ; < = > ? @ [ \  ] ^ _\n` {  \|  } ~ or Space |
| `POSITIVE_AMOUNT` | Enter number and positive number only. |
| `PIPE` | Not allows special characters: \| |
| `ENGLIST` *(sic)* | Recipient Name should be in English only. It is mandatory for BAHTNET service and maximum is 140 length. |
| `EXPORT_WORNING` *(sic)* | Warning about export CSV file!! |
| `EXPORT_ERROR` | Please enter the information in all required fields before generate txt file for upload. |
| `EXPORT_INVOICE_WHT_NULL` | Invoice/WHT sheet has been open for required value, please enter the details before generate txt file for upload. |
| `EXPORT_WHT_NULL` | WHT sheet has been open for required value, please enter WHT details before generate txt file for upload. |
| `EXPORT_INVOICE_NULL` | Invoice sheet has been open for required value, please enter invoice details before generate txt file for upload. |
| `EXPORT_UNCHECK_INVOICE_WHT` | There is the information in Invoice/WHT sheet that has been hidden, please remove the details before generate txt file for upload. |
| `EXPORT_UNCHECK_INVOICE` | There is the information in invoice sheet that has been hidden, please remove the details before generate txt file for upload. |
| `EXPORT_UNCHECK_WHT` | There is the information in WHT sheet that has been hidden, please remove the details before generate txt file for upload. |
| `CLEAR_ALL_CONFIRM` | Do you want to clear all information? |
| `CLEAR_CREDIT_CONFIRM` | Do you want to clear all credit information? |
| `ACCOUNT_NO_PPY` | The information in this field must be numbers e.g. Mobile number, Citizen ID, Tax ID or E-wallet ID and not exceed the maximum length. |
| `WRONG_BANK` | Bank code was wrong, Please select bank code again. |
| `WRONG_FEE_CHANGE` | Fee charge was wrong, Please select fee charge again. |
| `SKIP_ROW` | Record shouldn't have space between row. |
| `PLEASE_SELECT` | Please select the information in this field. |
| `PLEASE_ENTER` | Please enter the information in this field. |
| `OVERLIMIT_CREDIT` | The maximum of invoice is 5 records. |
| `MANDOTARY_RECIPIENT_BAHTNET` *(sic)* | WHT Recipient Name in English is Mandatory for BAHTNET and not exceed maximun length. |
| `MANDOTARY_ADDRESS_BAHTNET` *(sic)* | WHT Recipient Address in English is mandatory for BAHTNET service and not exceed 70 maximum length. |
| `MANDATORY_PERCENTAGE_DIV` | Percentage of divident to net profit is mandatory for type of income no. 4b 1.4. |
| `SPECIAL_BAHTNET_70` | WHT Recipient Name in English is mandatory for BAHTNET service and not exceed 70 maximum length. |
| `WHT_INCOME_TYPE_MAX` | WHT Income type must not be more than 3 unique per transation. |
| `SPECIAL_BAHTNET_140` | WHT Recipient's name in English is mandatory for BAHTNET service and not exceed 140 maximum length. |
| `TEXT_ONLY_ENG_140` | Please check for allowed characters, numbers or special characters and not exceed 140 maximun length. |
| `POSITIVE_AMOUNT_DEDUCT_RATE` | The information in this field must be the number. |
| `AMOUNT_CREDIT` | The information in this field must be number and credit amount must be more than zero. |
| `WHTDeductRate` | The information in this field must be the number between 0 to 100. |
| `Payroll_Checkbox` | ระบบยังไม่รองรับการออกเอกสาร invoice และ WHT สำหรับบริการจ่ายเงินเดือน (Invoice/WHT not supported for payroll) |
| `Debit_error` | Debit account number must be a 10-digit number. |
| `Debit_Fee_error` | Debit fee account number must be a 10-digit number. |
| `SPECIAL_CHAR` | Not allows special characters: ! " #\n$ % & * +  ; < = > ? @ [ \  ] ^ _\n` {  \|  } ~ |
| `REMARK_INV` | Please check for allowed characters… not exceed 100 maximum length. Not allows special characters: ! " # $ % & * + ; < = > ? @ [ \ ] ^ _ ` { \| } ~ |
| `PIPE_MAX` | The information in this field must be number and and *(sic)* not exceed 15 maximum length. Not allows special characters: \| |
| `SMART_AMOUNT` | Amount must not exceed 2,000,000 Baht per transaction. (For SMART Payroll, SMART Credit, ORFT, PromptPay services). |
| `PROMPTPAY_AMOUNT` | Amount must not exceed 10,000 Baht per transaction. (For E-Wallet PromptPay services). |
| `RECIPIENT_ADDRESS_70` | …not exceed 70 maximum length. Not allows special chars … or Space |
| `TEXT_SPECIAL` | Please check for allowed characters… not exceed 140 maximun length. |
| `ACCOUNT_NUM` | SCB recipient account number must be a 10-digit number. |
| `SPECIAL_70` | …not exceed 70 maximum length. Not allows special characters … or Space |
| `ACCOUNT_PPY` | The information in this field must be numbers e.g. Mobile number, Citizen ID, Tax ID or E-wallet ID and not exceed the maximum length. |
| `SCB_CHECK_DIGIT` | The information in this field must be SCB account number. |
| `NO_THAI` | The information in this field is not allow Thai language. |
| `NO_CREDIT_SEQ_NO` | Please enter the information in credit seq no fields before generate txt file for upload. |
| `ALLOW_SPECIAL_70` | Please check for allowed characters… not exceed 70 maximum length. |
| `ACCOUNT_NUMBER_CREDIT_ACC_NO` | The credit account number is in an invalid format. |
| `ACCOUNT_NUMBER_DEBIT_ACC_NO` | The debit account number is in invalid format. |
| `ACCOUNT_NUMBER_DEBIT_FEE_ACC_NO` | The debit fee account number is in invalid format. |
| `TEXT_CUSTOMER_BATCH_REF` | Please check for allowed characters… not exceed 12 maximun length. |
| `ERROR_SYSTEM_REFERENCE_ID` | Please check for allowed characters… not exceed 18 maximum length. |
| `TEXT_ONLY_ENG_NUM_SPECIAL` | Please check for allowed characters… not exceed 20 maximum length. |

*Field-length business rules derivable from the above: Customer Batch Ref ≤12, System Reference ID ≤18, Customer Txn Ref ≤20, recipient address ≤70, recipient name/remark ≤140, invoice remark/description ≤100, amount ≤15 chars incl. 2 decimals. SMART/ORFT/PromptPay per-txn cap 2,000,000; E-Wallet PromptPay cap 10,000.*

---

### 3. `Payment` sheet (sheet2) — layout

Dimension `A1:V267`. Columns **A–H visible**; **I, J, K, L hidden** (still part of the credit table — VBA toggles their visibility by product); **M–T hidden helper/scratch columns**.

#### 3.1 Configuration block (rows 1–7)
Two label/value pairs per row: labels in cols **B** (left) and **D/E** (right); the user-entry cells are the adjacent C-column / merged E:F / merged C5:C6 / merged F5:F6 cells. Data-validation *info prompts* are attached to the **label** cells (listed under "prompt-on" below).

| Field | Label cell (text) | Entry cell | Currently stored value | Validation / prompt |
|---|---|---|---|---|
| Customer File Ref (อ้างอิงไฟล์รายการ) | `B2` | `C2` | **`050526154634RFT`** (auto-generated; embeds timestamp + product code `RFT`) | prompt on `B2`: "auto-generated, no need to fill" |
| Customer Batch Ref (อ้างอิงกลุ่มรายการ) | `D2` | `E2:F2` (merged) | (empty) | prompt on `D2`: "auto-generated"; validated ≤12 chars (`TEXT_CUSTOMER_BATCH_REF`) |
| Debit Account (เลขที่บัญชีตัดเงิน) | `B3` | `C3` | (empty) | prompt on `B3`: mandatory, SCB 10-digit (e.g. 9991888887) |
| Select transfer/payment service (เลือกบริการโอน/ชำระเงิน) | `D3` | radio buttons (see 3.3) | — | prompt on `D3`: mandatory |
| Debit Fee Account (เลขที่บัญชีหักค่าธรรมเนียม) | `B4` | `C4` | (empty) | prompt on `B4`: mandatory, SCB 10-digit |
| Select Product | `D4` | `E4:F4` (merged) | **`--Select--`** | **list dropdown** (x14) — source varies by radio (see 3.3) |
| Value Date (วันที่รายการมีผล / Value Date (DD/MM/YYYY)) | `B5` + `B6` | `C5:C6` (merged) | (empty) | prompt on `B5`: mandatory, format DD/MM/YYYY (accepts พ.ศ. or ค.ศ.), no back-dating, business day only |
| Select WHT/Invoice (เลือก WHT/Invoice) | `D5` | checkboxes (see 3.3) | — | prompt on `D5`: optional; WHT/Invoice not supported for payroll |
| System Reference ID | `E5` | `F5:F6` (merged) | (empty) | prompt on `E5`: optional, "รหัสบริษัท"; validated ≤18 chars |

Merged ranges on this sheet: `E2:F2`, `E4:F4`, `E3:F3`, `C5:C6`, `F5:F6`, `G2:L6` (a large info/legend panel, cell `G2`=`" "`), and **`A7:XFD7`** (full-width separator row 7).

**Hidden helper cells** (row 2): `M2="TBPPPayroll"`, `N2="TBBank"`, `O2="TBFeeOther"`, `P2="TBServiceType"` — table-name strings the VBA reads to know which lookup to bind to each credit column for the current product. Rows 9–12 of N–S hold per-example-row defaults (bank code, `BEN`, `Code`, `Y`,`Y`,`Y`). `M8="1"` seeds the Credit Seq. No. helper.

#### 3.2 Credit (recipient) table — column headers at **row 8**
One data row per recipient starting row 9; each becomes one **TXNDET** record (+ nested INVDET/WHTCER if the Invoice/WHT checkbox is on). `*` = mandatory. Header text is bilingual (`\n` splits Thai/English).

| Col | Vis | Header (Thai / English) | Notes |
|---|---|---|---|
| **A** | ✔ | ลำดับที่ / Credit Seq. No. | row sequence |
| **B** | ✔ | *เลือกธนาคาร / Bank Code | dropdown, source = product-specific bank sub-list |
| **C** | ✔ | *เลขที่บัญชี / หมายเลขพร้อมเพย์ / Credit Account Number / PromptPay ID | 10-digit for SCB; PromptPay ID otherwise |
| **D** | ✔ | *ชื่อผู้รับเงิน / Recipient Name (TH/EN) | ≤140; BAHTNET → English/number only, no special chars |
| **E** | ✔ | *จำนวนเงิน / Amount | > 0.00, ≤15 chars incl. 2 decimals |
| **F** | ✔ | อ้างอิงรายการ / Customer Transaction Ref. | optional, ≤20, limited specials `- ( ) : / ' , . \| ^ \ #` |
| **G** | ✔ | หักค่าธรรมเนียมจาก / Fee Charge | dropdown OUR/BEN/SHA per product |
| **H** | ✔ | เลขที่สาขา / Branch Code | 4-digit |
| **I** | ✖(hidden) | วัตถุประสงค์ของธุรกรรม / Service Type | dropdown (TBServiceType); shown for SMART/BAHTNET |
| **J** | ✖(hidden) | หมายเลขโทรศัพท์ผู้รับเงิน / SMS Notification | recipient mobile, ≤3 numbers |
| **K** | ✖(hidden) | อีเมล์ผู้รับเงิน / Email Notification/Receiving Document | ≤100, no `\|` |
| **L** | ✖(hidden) | หมายเหตุสำหรับเอกสารแจ้งชำระเงิน / Payment Advice Remark (Txn level) (≤200 chars) | optional |

#### 3.3 Form controls (from `xl/ctrlProps/*` + `xl/drawings/vmlDrawing1.vml`)
These are the interactive shapes on the Payment sheet and their assigned macros:

| Caption | Type | Control name | Macro | Effect |
|---|---|---|---|---|
| **Generate Text File** | Button | Button 22 | `Export.Export` | builds & writes the pipe-delimited upload file |
| **Clear Credit** | Button | Button 23 | `ClearCredit` | clears credit rows only |
| **Clear All** | Button | Button 50 | `Clear.Clear` | clears everything |
| **WHT** | Checkbox | `WHTChk` | `Sheet1.WHTChk_Click` | shows/hides WHT sheet requirement |
| **Invoice** | Checkbox | `InvoiceChk` | `Sheet1.InvoiceButt_Click` | shows/hides Invoice sheet requirement |
| **Payroll** | Radio *(default checked, firstButton)* | Option Button 10165 | `Sheet1.Payroll_Click` | binds Product dropdown → `TBPPPayroll` (A250:A258) |
| **SCB Transfer** | Radio | Option Button 10702 | `Sheet1.SCBTransfer_Click` | binds → `TBPPSCBTransfer` (A261:A262) |
| **Other Bank Transfer** | Radio | Option Button 10707 | `Sheet1.OtherBankTransfer_Click` | binds → `TBPPOtherBankTransfer` (A265:A268) |
| **PromptPay** | Radio | Option Button 10722 | `Sheet1.PromptPay_Click` | binds → `TBPPPromptPay` (A271) |

The four radios form one group (the "เลือกบริการโอน/ชำระเงิน" selector at `D3`); clicking one rewrites the `E4` Product dropdown source and the credit-column bindings. A logo image (`image7.png`) sits at the top-left of the sheet (drawing2, anchored ~row 0 / row 5).

---

### 4. `Invoice` sheet (sheet3) — header row (row 1)
Dimension `A1:K9` (hidden sheet). One data row per recipient → one **INVDET** record (10 data fields = cols B–K; col A `Code` is the internal record identifier). `*` mandatory.

| Col | Header (Thai / English) |
|---|---|
| **A** | `Code` (record/identifier) |
| **B** | ลำดับที่ / Credit Seq. No. |
| **C** | *วันที่แจ้งหนี้ / Invoice Date |
| **D** | *Invoice Number / หมายเลขใบแจ้งหนี้ |
| **E** | *จำนวนแจ้งหนี้ / Invoice Amount |
| **F** | คำอธิบายใบแจ้งหนี้ / Invoice Description (≤100 Char) |
| **G** | หมายเลขใบสั่งซื้อ / Purchase Order No. |
| **H** | ภาษีมูลค่าเพิ่ม / VAT Amount |
| **I** | หัก ณ ที่จ่าย / WHT Amount |
| **J** | *ยอดสุทธิในแจ้งหนี้ / Invoice Net Amount |
| **K** | หมายเหตุใบแจ้งหนี้ / Remark for Invoice (≤100 Char) |

Validations are prompt-only info tooltips on B1–F1. Max 5 invoice records (`OVERLIMIT_CREDIT`).

---

### 5. `WHT` sheet (sheet4) — header row (row 1)
Dimension `A1:BJ25` (hidden sheet). One data row per recipient → one **WHTCER** record. Layout = **certificate header (cols A–V)** + **5 repeating income-detail blocks (W–AD, AE–AL, AM–AT, AU–BB, BC–BJ)**, each block 8 columns.

#### 5.1 Certificate header (cols A–V)
| Col | Header (Thai / English) | Notes |
|---|---|---|
| **A** | `Code` | record identifier |
| **B** | ลำดับที่ / Credit Seq. No. | |
| **C** | เลขที่ / WHT Book No. | |
| **D** | เลขประจำตัวผู้เสียภาษีอากร (ผู้มีหน้าที่หักฯ) / WHT Payer Tax ID | |
| **E** | ผู้มีหน้าที่หักภาษี ณ ที่จ่าย / WHT Payer Name | |
| **F** | ที่อยู่ 1 / WHT Payer Address Line 1 | |
| **G** | ที่อยู่ 2 / WHT Payer Address Line 2 | |
| **H** | ที่อยู่ 2 / WHT Payer Address Line 2 ⚠️ *(dup label — actually Address Line 3)* | |
| **I** | *เลขที่ผู้ถูกหักฯ / Recipient Tax ID for WHT | mandatory |
| **J** | *ชื่อผู้ถูกหักฯ / WHT Recipient Name (TH/EN) | mandatory; BAHTNET → English only |
| **K** | *ที่อยู่ผู้ถูกหักฯ / WHT Recipient Address Line 1 | mandatory |
| **L** | ที่อยู่ 2 / WHT Recipient Address Line 2 | |
| **M** | ที่อยู่ 3 / WHT Recipient Address Line 3 | |
| **N** | ระบุชื่อผู้รับอื่น / Alternative Recipient Name for WHT | |
| **O** | *แบบ / WHT Form Type | **dropdown** → TBWHTType |
| **P** | WHT Form Type Code | helper (resolved code) |
| **Q** | *วันเดือนหรือปีภาษีที่จ่าย / WHT Deduct Date | mandatory |
| **R** | *ผู้จ่ายเงิน / WHT Pay Type | **dropdown** → TBWHTPayType |
| **S** | WHT Pay Type Code | helper (resolved code) |
| **T** | ระบุกรณีเลือกผู้จ่ายเงิน = อื่นๆ (4) / WHT Remark for Pay Type | required when Pay Type=4 |
| **U** | No. of WHT Detail | count of populated income blocks |
| **V** | Total WHT Detail Amount | sum |

#### 5.2 Income-detail block (repeated 5×)
Block *n* occupies 8 columns; layout identical for each:

| Offset | Block 1 | Block 2 | Block 3 | Block 4 | Block 5 | Header (Thai / English) |
|---|---|---|---|---|---|---|
| block# label | W (`1`) | AE (`2`) | AM (`3`) | AU (`4`) | BC (`5`) | block number |
| identifier | X | AF | AN | AV | BD | WHT Detail Record Identifier*n* |
| income type | **Y** | **AG** | **AO** | **AW** | **BE** | *ประเภทเงินได้ / WHT Income Type (dropdown→TBIncomeType) |
| description | Z | AH | AP | AX | BF | คำอธิบายประเภทเงินได้ / Income Description |
| rate % | AA | AI | AQ | AY | BG | % อัตรา / WHT Deduct Rate % (0–100) |
| % div. | AB | AJ | AR | AZ | BH | อัตราอื่นๆ ของกำไรสุทธิ / Percentage of Dividend to Net Profit (required for income 4b1.4) |
| amount | AC | AK | AS | BA | BI | จำนวนเงินที่จ่าย / Income Type Amount |
| WHT amount | AD | AL | AT | BB | BJ | ภาษีที่หักและนำส่ง / WHT Amount |

Business rule: max **3 unique** income types per transaction (`WHT_INCOME_TYPE_MAX`).

---

### 6. `File_Info` sheet (sheet6) — version + changelog
Full content (only cols A/B, rows 1,3,4,5):

| Cell | Value |
|---|---|
| `A1` | กรุณาอย่าลบ หรือแก้ไขตัวไฟล์! (Please do not delete or edit anything in this file!) |
| `A3` / `B3` | **Toolkit Version** = **`1.3.8`** |
| `A4` | ลบ 2 bank Ascend , Bank x  *(changelog: removed 2 banks — Ascend, Bank x)* |
| `A5` | แก้ไข CLICX ให้ไปใช้ Bank Short Name (Thai) *(changelog: fixed CLICX to use Thai bank short name)* |

The changelog is only these two lines (A4, A5). The version string `1.3.8` here is the authoritative in-file version.

---

### 7. Instructions sheet (sheet1) — image-only
Dimension `D2:G9`, **zero text cells**. Content is **6 embedded PNGs** (`image1.png`–`image6.png`, wired via `xl/drawings/drawing1.xml` + its rels), floated over the sheet. A re-implementer gets **no machine-readable instruction text** from this sheet — the how-to-enable-macros guidance exists only as screenshots. (`image7.png` is the Payment-sheet logo via drawing2.)

---

### 8. Named ranges & data-validation dropdowns

#### 8.1 Defined names (`xl/workbook.xml`) — only 2, both problematic
| Name | Refers to | Status |
|---|---|---|
| `SPECIAL_BAHTNET_70` | `Master_data!$A$357` | ⚠️ **Stale/misaligned** — `A357` is actually the key `NO_CREDIT_SEQ_NO`, **not** `SPECIAL_BAHTNET_70` (which lives at `A335`). The named range points 22 rows off. |
| `TBBankBNT` | `[1]Master_data!#REF!` | ⚠️ **Broken external `#REF!`** — `[1]` = external workbook `/Users/S91763/Documents/CPX_Toolkit_Template_1.0.6.xls` (a developer's local v1.0.6 file, user `S91763`). Dead reference. |

The 23 "TB…" tables are **Excel Tables** (structured references), *not* defined names — resolve them by the `A..:B..` ranges given in §2.

#### 8.2 Data-validation dropdowns (list type)
**Payment sheet (`x14` list validations):**
| Cells | Source range | Meaning |
|---|---|---|
| `E4` | `Master_data!$A$250:$A$258` | Product selector — **currently bound to Payroll list** (the default radio); VBA rewrites this per radio |
| `B9 B10 B11 B12` | `Master_data!$A$88:$A$125` | Bank Code dropdown (credit rows 9–12), full `TBBank` list |
| `B16` | `Master_data!$A$88:$A$124` | Bank Code dropdown (one row uses A88:A124 — excludes last bank `098`) ⚠️ inconsistent range vs the block above |

All other Payment-sheet validations (`B2,B3,B4,B5,C8,D2,D3,D5,E5,E8,F8,G8,H8,I8,J8,K8,L8`) are **prompt-only** info tooltips (no list constraint); the actual credit-column dropdowns (Bank, Fee, Service Type) are applied dynamically by VBA per active row, keyed off the `M2:P2` table-name helpers.

**WHT sheet (inline list validations — literal comma-lists, not table refs):**
| Cells (sparse — only the rows that had a dropdown when saved) | List values (= labels; codes resolved via Master_data) |
|---|---|
| `O2 O3 O4 O11` | `ภงด 1 ก, ภงด 2, ภงด 3, ภงด 1 ก พิเศษ, ภงด 2 ก, ภงด 3 ก, ภงด 53` (WHT Form Type) |
| `R2 R3 R4 R6 R17:T17` | `ผู้จ่ายออกครั้งเดียว, ออกให้ตลอดไป, หักภาษี ณ ที่จ่าย, อื่นๆ` (WHT Pay Type) |
| `Y2 Y3 AG2 AO2 AO3 AO4 AO5 AW2 BE2` | `1,2,3,4a,4b1.1,4b1.2,4b1.3,4b1.4,4b2.1,4b2.2,4b2.3,4b2.4,4b2.5,5,6` (Income Type) |

The WHT dropdown `sqref` sets are sparse/irregular (e.g. Pay-Type list applied to `R17:T17`, a 3-cell span) — VBA re-applies list validation to each active data row on demand. **Invoice sheet** has no list dropdowns (prompt-only on B1–F1).

---

### 9. Quirks / traps a re-implementer must know
- **VBA code name "Sheet1" == the Payment tab**, not the Instructions tab. Invoice=Sheet3, WHT=Sheet4, Master_data=Sheet5.
- **Bank sub-lists are product-dependent** and the `TBBankWithout014` table is a **misnomer** (it drops `080`, keeps `014`). Never bind the bank dropdown to `TBBank` blindly — pick the sub-list by product (SCB-only=`TBBankPAY`, PromptPay=`TBBankPPY`(code `111`), BAHTNET=`TBBankBNT1`, SMART=`TBBankSmartCredit`).
- **Saved-state inconsistency:** Product radio defaults to *Payroll* and `E4` dropdown is bound to the Payroll list, yet the stored Customer File Ref `050526154634RFT` ends in `RFT` (a leftover from a prior Other-Bank-Transfer session). Treat `C2` as regenerated at export, not authoritative.
- **Instructions are images only** — no text to port.
- **Two defective defined names** (`SPECIAL_BAHTNET_70` misaligned by 22 rows; `TBBankBNT` = broken `#REF!` to an external dev file).
- **Column visibility ≠ column existence**: Payment cols I–L are hidden in the saved (Payroll) state but are live credit-table fields; M–T are hidden VBA scratch columns.
- **Numerous label/message typos** are baked into the data and are load-bearing keys — reproduce them exactly, do not "correct": table `TBPromptPayPoxcy` / header "PromptPay Poxy"; service types `Dividened`, `Thai Lobour`; error keys `ENGLIST`, `EXPORT_WORNING`, `MANDOTARY_RECIPIENT_BAHTNET`, `MANDOTARY_ADDRESS_BAHTNET`; message text "maximun", "divident", "transation", "and and".
- **WHT header col H** is mislabeled "Address Line 2" (duplicate of G) but is functionally Payer Address Line 3.
- **Code sets are non-sequential** (WHT form types 01/03/04/11/12/13/53; service types include a jump to 59 in `TBServiceTypeSmart`). Map by explicit lookup, never by ordinal position.

*(Extraction script + raw XML parts retained at `/private/tmp/claude-501/-Users-nest-Documents-pguard/c7cb34b5-0bee-46b1-afc9-39a9331d53a3/scratchpad/extract.py` and `.../scratchpad/xlsx_extract/` if re-verification is needed.)*


---

## `Validation.bas` — Master Schema & Validation Rulebook

`Validation.bas` (VB_Name = `"Validation"`) is a **standard module** (not a sheet object). It holds the shared validation grammar for all three data sheets. The per-row *orchestration* (`ValidateRowInfo`) lives in the sheet objects (`Sheet1`/`Sheet3`/`Sheet4`); this module supplies the **field-level validators**, the **date/amount/account/tax-ID/email rules**, the **character-class predicates**, the **SCB check-digit algorithm**, and the **sheet-level drivers** (`VallidateAll`, `ValidateSheetByName`, `validateSystemReferenceId`).

> **No `Option Explicit`.** Many working variables (`errMsg`, `dateString`, `msg`, `dateInput`, `dateCurrent`, `ProductCode`, `checkValid`, `checkEngExist`, `listOfEndChar`, `checkExist`, `Index`, `arrEmail`, `aEmail`, `sChar`…) are **implicit procedure-scoped Variants**. A re-implementer must treat them as locals, not module state.

> **Flagging is delegated.** Validators here **return an error string** (usually an error *code*); they do **not** paint cells. The visual flagging (red/yellow fill, cell comment, error counter) is done by `InvalidCell` / `validCell` / `CountErrorMsg` in **`Util.bas`** (documented in §3 below because Validation calls into them via `validateSystemReferenceId`).

---

### 1. Constants, globals & module variables

#### 1a. Declared **in `Validation.bas`**

| Name | Scope | Type | Value | Notes |
|---|---|---|---|---|
| `idxHeader` | Public | Integer | `8` | Payment sheet header row. Data credit rows start at `idxHeader+1` = **row 9**. |
| `DebitCode` | Public | String | `"BCHDET"` | Debit/batch record code. |
| `HeaderCode` | Public | String | `"HEADER"` | File header record code. |
| `TBBatchDetails` | Public | String | `"TBBatchDetails"` | ListObject name (Payment batch table). |
| `TBCreditInfo` | Public | String | `"TBCreditInfo"` | ListObject name (Payment credit table). |
| `TBInvoiceDetail` | Public | String | `"TBInvoiceDetail"` | ListObject name (Invoice sheet). |
| `TBWHTCertificate` | Public | String | `"TBWHTCertificate"` | ListObject name (WHT sheet). |
| `TBProductCode` | Public | String | `"TBProductCode"` | Master_data dropdown table. |
| `TBPromptPayPoxcy` | Public | String | `"TBPromptPayPoxcy"` | Master_data table (note the **typo "Poxcy"**, presumably "Policy" — must match the actual ListObject name). |
| `TBWHTType` | Public | String | `"TBWHTType"` | Master_data table. |
| `TBWHTPayType` | Public | String | `"TBWHTPayType"` | Master_data table. |
| `TBIncomeType` | Public | String | `"TBIncomeType"` | Master_data table. |
| `TBServiceType` | Public | String | `"TBServiceType"` | Master_data table. |
| `colCreditTransactionReference` | **Private** `Const` | Integer | `3` | **Appears unused within this module.** |
| `colDebitBatchRef` | **Private** `Const` | Integer | `2` | **Appears unused within this module.** |
| `pleaseSelect` | Public | String | `"--Select--"` | Sentinel dropdown value ("nothing selected"). |
| `defaultCustomerBatchRef` | Public | String | `"MMDDYYHHMMSS"` | Placeholder shown in the customer batch-ref cell. |
| `msgSelect` | Public | String | `"PLEASE_SELECT"` | Error **code** (human text `"Please select the information in this field."` in trailing comment). |
| `msgEnter` | Public | String | `"PLEASE_ENTER"` | Error **code** (human text `"Please enter the information in this field."`). |
| `msgManBahtNet` | Public | String | `"MANDOTARY_RECIPIENT_BAHTNET"` | Error code (note misspelling "MANDOTARY"). |
| `msgManAddress` | Public | String | `"MANDOTARY_ADDRESS_BAHTNET"` | Error code. |
| `msgManPercentage` | Public | String | `"MANDATORY_PERCENTAGE_DIV"` | Error code. |
| `CountError` | **Global** | Integer | (runtime) | Scratch global; mirrors the `N1` error-count cell (see `Util.CountErrorMsg`). |
| `addressProductCodeForValidate` | Public | String | `"M1"` | Cell holding the resolved product code, read by `compareDateWithCurrentDate`. |

#### 1b. Constants the task lists that actually live in **other modules** (cross-reference)

The task's "constant table" spans modules. For a re-implementer, here is where the rest are defined:

| Name | Value | Defined in |
|---|---|---|
| `CreditCode` | `"TXNDET"` | **Sheet1.bas** (private `Const`) |
| `delim` | `"|"` | **Export.bas** (Public) — the pipe field delimiter |
| `addressCountError` | `"N1"` | **Util.bas** — the error-count cell on Payment |
| `addressCustomFileRef` | `"C2"` | **Util.bas** |
| `addressDebitAcc` | `"C3"` | **Util.bas** |
| `addressDebitAccFee` | `"C4"` | **Util.bas** |
| `addressValueDate` | `"C5"` | **Util.bas** |
| `addressCustomBatchRef` | `"E2"` | **Util.bas** |
| `addressDropDownProductType` | `"E4"` | **Util.bas** |
| `addressSystemReferenceId` | `"E6"` | **Util.bas** (used by `validateSystemReferenceId` here) |
| `addressProductCode` | `"M1"` | **Sheet1.bas** (distinct name, same `M1` cell as `addressProductCodeForValidate`) |

---

### 2. Error-code catalogue (the `TBErrorMessage` table)

Validators return **error codes** (strings). `Util.FindErrorMessage(code)` looks the code up in **`Master_data` ListObject `TBErrorMessage`** (range **`A301:B364`**, col A = code, col B = message) and returns the message; **if the code is not found it returns `""`**, and `InvalidCell` then falls back to putting the **raw string** into the cell comment. This matters because **several validators return a literal English sentence instead of a code** (e.g. `ValidateTextFormatDebit` returns `"Debit account number must be a 10-digit number."`); those never match a key and are shown verbatim.

Below is the **complete `TBErrorMessage` table as shipped** (63 rows; `\n` = embedded newline). "Thrown by" is annotated from a cross-module grep; codes marked *(Validation.bas)* are returned by functions in this module.

| Code (col A) | Message (col B) | Thrown by |
|---|---|---|
| `PRODUCT` | Please select the information in this field. | Sheet1 |
| `NUMBER` | The information in this field must be number. | Validation (`ValidateTextFormat` NUMBER/TAX_ID) |
| `FIX_4_NUMBER` | The information in this field must be in number with 4 digits. | Validation (`FIX_4_NUMBER`) |
| `AMOUNT` | The information in this field must be number. | Validation (amount validators) |
| `AMOUNT_DECIMAL` | Decimal number cannot more than 2 digit. | Validation (all amount validators, >2 dp) |
| `EMAIL` | The information in this field must be email and not exceed 100 maximum length.\n\nNot allows special characters: \| | Validation (`EMAIL_ADDRESS`) |
| `PHONE_10` | The information in this field must be mobile number 10. | *(orphan — not thrown by quoted literal)* |
| `PHONE` | The information in this field must be mobile number and not exceed 3 maximum mobile numbers. | Validation (`ValidateTextFormatPhoneNum`) |
| `DATE` | Data format is not correct. | Validation (`validateDate`) |
| `SPECIAL_SPACE` | Not allows special characters: ! " #\n$ % & * + ; < = > ? @ [ \\ ] ^ _\n` { \| } ~ or Space | Validation (`NOT_SPECIAL_CHAR`) |
| `POSITIVE_AMOUNT` | Enter number and positive number only. | *(orphan)* |
| `PIPE` | Not allows special characters: \| | Validation (`TEXT_NO_PIPE`) |
| `ENGLIST` | Recipient Name should be in English only. It is mandatory for BAHTNET service and maximum is 140 length. | Validation (`TEXT_ONLY_ENG`) |
| `EXPORT_WORNING` | Warning about export CSV file!! | Export |
| `EXPORT_ERROR` | Please enter the information in all required fields before generate txt file for upload. | Export |
| `EXPORT_INVOICE_WHT_NULL` | Invoice/WHT sheet has been open for required value… | Export |
| `EXPORT_WHT_NULL` | WHT sheet has been open for required value… | Export |
| `EXPORT_INVOICE_NULL` | Invoice sheet has been open for required value… | Export |
| `EXPORT_UNCHECK_INVOICE_WHT` | There is the information in Invoice/WHT sheet that has been hidden… | Export |
| `EXPORT_UNCHECK_INVOICE` | There is the information in invoice sheet that has been hidden… | Export |
| `EXPORT_UNCHECK_WHT` | There is the information in WHT sheet that has been hidden… | Export |
| `CLEAR_ALL_CONFIRM` | Do you want to clear all information? | Clear |
| `CLEAR_CREDIT_CONFIRM` | Do you want to clear all credit information? | Clear |
| `ACCOUNT_NO_PPY` | The information in this field must be numbers e.g. Mobile number, Citizen ID, Tax ID or E-wallet ID and not exceed the maximum length. | *(orphan; cf. `ACCOUNT_PPY`)* |
| `WRONG_BANK` | Bank code was wrong, Please select bank code again. | Sheet1 |
| `WRONG_FEE_CHANGE` | Fee charge was wrong, Please select fee charge again. | Sheet1 |
| `SKIP_ROW` | Record shouldn't have space between row. | *(via variable; Util MsgBox uses same text)* |
| `PLEASE_SELECT` | Please select the information in this field. | Validation (`msgSelect`) + sheets |
| `PLEASE_ENTER` | Please enter the information in this field. | Validation (`msgEnter`, `ValidateAmount`/`ValidateAmountCredit` blank) |
| `OVERLIMIT_CREDIT` | The maximum of invoice is 5 records. | Sheet3 |
| `MANDOTARY_RECIPIENT_BAHTNET` | WHT Recipient Name in English is Mandatory for BAHTNET and not exceed maximun length. | Validation (`msgManBahtNet`) / Sheet4 |
| `MANDOTARY_ADDRESS_BAHTNET` | WHT Recipient Address in English is mandatory for BAHTNET service and not exceed 70 maximum length. | Validation (`msgManAddress`) / Sheet4 |
| `MANDATORY_PERCENTAGE_DIV` | Percentage of divident to net profit is mandatory for type of income no. 4b 1.4. | Validation (`msgManPercentage`) / Sheet4 |
| `SPECIAL_BAHTNET_70` | WHT Recipient Name in English is mandatory for BAHTNET service and not exceed 70 maximum length. | Validation (`TEXT_ONLY_ENG_BAHTNET70`) |
| `WHT_INCOME_TYPE_MAX` | WHT Income type must not be more than 3 unique per transation. | Sheet4 (via variable) |
| `SPECIAL_BAHTNET_140` | WHT Recipient's name in English is mandatory for BAHTNET service and not exceed 140 maximum length. | Validation (`TEXT_ONLY_ENG_BAHTNET140`, `ValidateTextFormatBahtNet`) |
| `TEXT_ONLY_ENG_140` | Please check for allowed characters, numbers or special characters and not exceed 140 maximun length. | Validation (`TEXT_ONLY_ENG_140`) |
| `POSITIVE_AMOUNT_DEDUCT_RATE` | The information in this field must be the number. | *(orphan; commented-out alt in `ValidateAmount`/`WHTPercentage`)* |
| `AMOUNT_CREDIT` | The information in this field must be number and credit amount must be more than zero. | Validation (`AMOUNT_CREDIT`, promptpay/smart floor) |
| `WHTDeductRate` | The information in this field must be the number between 0 to 100. | Validation (`ValidateAmountWHTPercentage`, `WHTDeductRate`) |
| `Payroll_Checkbox` | ระบบยังไม่รองรับการออกเอกสาร invoice และ WHT สำหรับบริการจ่ายเงินเดือน | Sheet1 (Thai: payroll product can't emit Invoice/WHT) |
| `Debit_error` | Debit account number must be a 10-digit number. | Validation (`ValidateTextFormatDebit`) |
| `Debit_Fee_error` | Debit fee account number must be a 10-digit number. | *(cf. `ValidateTextFormatDebitFee`; returns literal, not this code)* |
| `SPECIAL_CHAR` | Not allows special characters: ! " #\n$ % & * + ; < = > ? @ [ \\ ] ^ _\n` { \| } ~ | Validation (`NO_SPECIAL_CHAR`, tax/income desc) |
| `REMARK_INV` | Please check for allowed characters… not exceed 100 maximum length.\nNot allows special characters: … | Validation (`ValidateTextFormatRemarkInv`) |
| `PIPE_MAX` | The information in this field must be number and and not exceed 15 maximum length.\nNot allows special characters: \| | *(commented-out alt in `ValidateTextFormatRecipientTax`)* |
| `SMART_AMOUNT` | Amount must not exceed 2,000,000 Baht per transaction.\n(For SMART Payroll, SMART Credit, ORFT, PromptPay services). | Validation (`ValidateAmountSmart`) |
| `PROMPTPAY_AMOUNT` | Amount must not exceed 10,000 Baht per transaction.\n(For E-Wallet PromptPay services). | Validation (`ValidateAmountPromptpay`) |
| `RECIPIENT_ADDRESS_70` | Please check for allowed characters… not exceed 70 maximum length.\nNot allows special characters: … or Space | *(orphan; cf. `ALLOW_SPECIAL_70`/`SPECIAL_70`)* |
| `TEXT_SPECIAL` | Please check for allowed characters, numbers or special characters and not exceed 140 maximun length. | Validation (`ValidateTextFormatRecipientName`) |
| `ACCOUNT_NUM` | SCB recipient account number must be a 10-digit number. | Validation (`ValidateTextFormatSCBAccount`) |
| `SPECIAL_70` | Please check… not exceed 70 maximum length.\nNot allows special characters: … or Space | Validation (`ValidateTextFormatRecipientAdds` NOT_SPECIAL_CHAR, `ValidateTextFormatBahtNet` NOT_SPECIAL_CHAR) |
| `ACCOUNT_PPY` | The information in this field must be numbers e.g. Mobile number, Citizen ID, Tax ID or E-wallet ID and not exceed the maximum length. | Validation (`ValidateTextFormatAccount`, `ACCOUNT_NUMBER_PPY`) |
| `SCB_CHECK_DIGIT` | The information in this field must be SCB account number. | Validation (`ValidateTextFormatSCBAccount`, check-digit fail) |
| `NO_THAI` | The information in this field is not allow Thai language. | Validation (`NOTTHAI`) |
| `NO_CREDIT_SEQ_NO` | Please enter the information in credit seq no fields before generate txt file for upload. | Export |
| `ALLOW_SPECIAL_70` | Please check for allowed characters, numbers or special characters and not exceed 70 maximum length. | Validation (`ValidateTextFormatRecipientAdds` length/SPECIAL_CHAR) |
| `ACCOUNT_NUMBER_CREDIT_ACC_NO` | The credit account number is in an invalid format. | Validation (`ValidateTextFormat`/`SCBAccount` when `strInput=0`) |
| `ACCOUNT_NUMBER_DEBIT_ACC_NO` | The debit account number is in invalid format. | Validation (`ValidateTextFormatSCBAccount` DEBIT_ACC, `=0`) |
| `ACCOUNT_NUMBER_DEBIT_FEE_ACC_NO` | The debit fee account number is in invalid format. | Validation (`ValidateTextFormatSCBAccount` DEBIT_FEE_ACC, `=0`) |
| `TEXT_CUSTOMER_BATCH_REF` | Please check for allowed characters, numbers or special characters and not exceed 12 maximun length. | Validation (`ValidateTextFormatCustomerBatchRef`) |
| `ERROR_SYSTEM_REFERENCE_ID` | Please check for allowed characters or special characters and not exceed 18 maximum length. | Validation (`validateSystemReferenceId`) |
| `TEXT_ONLY_ENG_NUM_SPECIAL` | Please check for allowed characters, numbers or special characters and not exceed 20 maximum length. | Validation (`TEXT_ONLY_ENG_NUM_SPECIAL`) |

> **Codes returned by validators here that are NOT keys** (so shown verbatim via the fall-through): `"SPECIAL"` (from `TEXT_ONLY_ENG_BAHTNET`), plus the many literal English sentences (see the amount/debit/tax/phone/income-desc validators). `"SPECIAL"` has **no matching row** → the cell comment literally reads `SPECIAL`. Treat as a latent copy bug (should have been `SPECIAL_BAHTNET_140` or similar).

---

### 3. How cells are flagged (called from here, defined in `Util.bas`)

`validateSystemReferenceId` (the only Validation.bas routine that paints cells) calls these. Reproduced because they are the flagging contract every validator ultimately feeds:

- **`CountErrorMsg(num As Integer)`** — reads `Payment!N1` (`addressCountError`) and writes `CInt(CountError)+num`. Increment on new error, decrement when an error clears.
- **`InvalidCell(row, col, msg, [sheetname])`** — if the cell isn't already red, `CountErrorMsg 1`; sets `Interior.ColorIndex = 3` (red); clears then adds a comment = `FindErrorMessage(msg)` if found else the raw `msg`; auto-sizes the comment.
  ```vba
  errMsg = FindErrorMessage(msg)
  ws.Cells(row, col).Interior.ColorIndex = 3 'color = vbRed
  If errMsg <> "" Then ws.Cells(row, col).AddComment errMsg Else ws.Cells(row, col).AddComment msg
  ```
- **`validCell(row, col, [sheetname])`** — if cell was red, `CountErrorMsg -1`; clears comments; then **colour = 27 (yellow-ish) if the row's col-1 cell is yellow, else 2 (white/none)**. So a valid cell inside a row otherwise flagged yellow inherits the yellow "row has issues" tint.
- **`getActiveSheet([sheetname])`** — defaults `sheetname` to `"Payment"`.

Colour legend used throughout: **3 = red (invalid)**, **27 = yellow (row-level warn)**, **2 = white/normal**, `vbYellow` on the anchor col-1 cell marks a warn row.

---

### 4. Data-validation (dropdown) helpers

#### `F_cellHasValidation(cell As Range) As Boolean`
Returns whether a cell has *any* Data Validation. Uses `On Error Resume Next` around `cell.Validation.Type`; if reading `.Type` errors (no validation), returns `False`.

#### `F_getIndexNrListValidation(cell As Range) As Long`
Returns the **1-based position** of the cell's current value within its **list** validation source, or a negative sentinel:

| Return | Meaning |
|---|---|
| `≥ 1` | Index of the selected item in the list |
| `-1` | Value not found (blank not in list, or list source changed) |
| `-2` | Validation exists but is **not** a list |
| `-3` | Cell has **no** validation |

Logic: if `F_cellHasValidation` and `Validation.Type = xlValidateList`:
- If `Formula1` starts with `"="` → it's a range ref → `WorksheetFunction.Match(cell.Value2, Range(Formula1), 0)` (guarded by `On Error Resume Next`, error→`-1`).
- Else → comma-split `Formula1`, loop, compare `CStr(cell) = item`, return `i+1`.

This index feeds `Util.getCodeConstantsFromMasterData(tableName, index)` in the sheet modules to translate a dropdown *label* into its *code* (e.g. product label → `"SPN"`).

---

### 5. Date validators

#### `validateDate(strInput As String) As String`
Returns `""` if valid, else `"DATE"`.

1. **Shape check** via `Like` patterns (returns `"DATE"` if fails):
   ```vba
   sMatch = (strInput Like "##/##/####") _
     And ((strInput Like "##/[0][1-9]/####") Or (strInput Like "##/[1][0-2]/####")) _
     And ((strInput Like "[0][1-9]/##/####") Or (strInput Like "[1-2][0-9]/##/####") Or (strInput Like "[3][0-1]/##/####"))
   ```
   → format `dd/mm/yyyy`; month ∈ 01–12; day ∈ 01–31 (00 and 32+ rejected by pattern). Year is any 4 digits (may be **พ.ศ. Buddhist**, converted later by `convDate`→`calYear`).
2. **Round-trip calendar check:** `dateString = Format(convDate(strInput), "dd/mm/yyyy")`, normalize any `" "`/`"-"`/`"."` separators to `"/"`, then:
   ```vba
   If IsEmpty(dateString) Or (Mid(dateString, 1, 5) <> Mid(strInput, 1, 5)) Then errMsg = "DATE"
   ```
   Comparing the first 5 chars (`dd/mm`) of the reparsed date against the input **catches impossible calendar dates**: e.g. `31/02/2024` passes the `Like` but `DateSerial(2024,2,31)` rolls to `02/03/2024`, so `"02/03" <> "31/02"` → `"DATE"`.

**Re-implementer notes:** The separator-replacement block is effectively dead for a `dd/mm/yyyy` `Format` output (never contains space/dash/dot). `Debug.Print` calls remain. Uses `convDate`/`calYear` from **Util.bas**.

#### `compareDateWithCurrentDate(dateString As String) As String`  *(Validation.bas version)*
Returns `""` if valid, else an error string. **Note a same-named `Function ... As Boolean` also exists in `Util.bas` (body commented out / dead)**; because VBA resolves same-module calls first, `ValidateTextFormat`'s `FUTURE_DATE` case binds to *this* String version.

1. First runs `validateDate`; if that fails, returns its `"DATE"` and exits.
2. `dateInput = convDate(dateString)`, `dateCurrent = convDate(Format(Now(),"dd/mm/yyyy"))`.
3. **Product-specific strict-future rule** (reads product code from `M1` = `addressProductCodeForValidate`):
   ```vba
   Select Case ActiveSheet.Name
       Case "Payment"
           ProductCode = ActiveSheet.range(addressProductCodeForValidate).value
           Select Case ProductCode
               Case "SPN", "SPN2", "SPN3", "SCN"
                   If dateInput <= dateCurrent Then compareDateWithCurrentDate = "Date format is not correct and should be future date only."
           End Select
   End Select
   ```
   → for **SPN/SPN2/SPN3/SCN** (standing/scheduled products) the value date must be **strictly after today**.
4. **Global past-date rule for all products:**
   ```vba
   If dateInput < dateCurrent Then compareDateWithCurrentDate = "Date format is not correct and should be future date only."
   ```
   → past dates rejected everywhere; **today** is allowed for non-SPN/SCN products, rejected for SPN*/SCN.

The returned string is a **literal sentence** (not a `TBErrorMessage` code), so it is displayed verbatim.

---

### 6. `ValidateTextFormat` — the central text dispatcher

#### `ValidateTextFormat(strPatternType, strInput, [minLength], [maxLength]) As String`
Empty input short-circuits to `""` (empty is "valid" here — mandatory-ness is enforced elsewhere). Then:

- **Length pre-checks** (note: these produce *literal* messages, unlike most validators):
  ```vba
  If (minLength > 0) And (Len(strInput) < minLength) Then errMsg = "Minimum length is " & minLength
  If (maxLength > 0) And (Len(strInput) > maxLength) Then errMsg = "Please check for allowed characters, numbers or special characters and not exceed " & maxLength & " maximum length."
  ```
- **`Select Case strPatternType`** — the full pattern → rule map:

| `strPatternType` | Rule | Error on fail |
|---|---|---|
| `ACCOUNT_NUMBER` | `strInput=0`→credit-acc code; elseif not numeric→`ACCOUNT_NUM` | `ACCOUNT_NUMBER_CREDIT_ACC_NO` / `ACCOUNT_NUM` |
| `ACCOUNT_NUMBER_PPY` | not numeric | `ACCOUNT_PPY` |
| `ACCOUNT_NUMBER`,`NUMBER`,`TAX_ID` | not numeric | `NUMBER` |
| `FIX_4_NUMBER` | not numeric **or** prior errMsg set | `FIX_4_NUMBER` |
| `EMAIL_ADDRESS` | comma-split; each via `IsEmailValid` | `EMAIL` |
| `DATE` | `validateDate(strInput)` | `DATE` |
| `FUTURE_DATE` | `compareDateWithCurrentDate(strInput)` | (its string) |
| `NOT_SPECIAL_CHAR` | `validateTextWithSpecialChar` true | `SPECIAL_SPACE` |
| `NO_SPECIAL_CHAR` | `validateTextWithSpecialChar` true | `SPECIAL_CHAR` |
| `TEXT_NO_PIPE` | contains `|` | `PIPE` |
| `TEXT_ONLY_ENG` | not `validateEngText` | `ENGLIST` |
| `TEXT_ONLY_ENG_BAHTNET` | not `validateEngText` | `SPECIAL` *(no such code → raw)* |
| `TEXT_ONLY_ENG_BAHTNET70` | not `validateEngTextNumber` | `SPECIAL_BAHTNET_70` |
| `TEXT_ONLY_ENG_BAHTNET140` | not `validateEngTextBNT` | `SPECIAL_BAHTNET_140` |
| `TEXT_ONLY_ENG_NUM_SPECIAL` | not `validateEngTextNumSpecialChar` | `TEXT_ONLY_ENG_NUM_SPECIAL` |
| `TEXT_ONLY_ENG_140` | not `validateEngTextNumChar` | `TEXT_ONLY_ENG_140` |
| `NOTTHAI` | not `validateEngTextNumSpecial` | `NO_THAI` |

> **`ACCOUNT_NUMBER` appears twice** in the `Select Case` (first branch and the merged `ACCOUNT_NUMBER,NUMBER,TAX_ID` branch). VBA evaluates the **first matching** `Case` only, so for `ACCOUNT_NUMBER` the `NUMBER`/`TAX_ID` branch is **unreachable** — the first branch wins.
> **`FIX_4_NUMBER`** does not enforce a length of 4 itself — the "4 digits" must be supplied by the caller's `minLength/maxLength`; the case only adds the numeric check (`Or errMsg <> ""` re-labels a prior length error as `FIX_4_NUMBER`).

---

### 7. Specialized text validators (per field type)

All share the boilerplate: empty→`""`; then a `min`/`max` length check that emits a **field-specific** code; then a `Select Case` on `strPatternType`.

| Function | Length-fail code | Pattern cases → fail code | Purpose |
|---|---|---|---|
| `ValidateTextFormatAccount` | `ACCOUNT_PPY` | `ACCOUNT_NUMBER`: not numeric→`ACCOUNT_PPY` | PromptPay proxy / generic acct (calls `CheckScbDigit` but ignores result). |
| `ValidateTextFormatRecipientName` | `TEXT_SPECIAL` | *(none — length only)* | Recipient name ≤140. |
| `ValidateTextFormatSCBAccount` | `ACCOUNT_NUM` | `ACCOUNT_NUMBER`/`DEBIT_ACC`/`DEBIT_FEE_ACC`: `=0`→ respective `ACCOUNT_NUMBER_*` code; not numeric→`ACCOUNT_NUM`; **check-digit fail→`SCB_CHECK_DIGIT`** | SCB 10-digit accounts w/ mod check. |
| `ValidateTextFormatRecipientAdds` | `ALLOW_SPECIAL_70` | `SPECIAL_CHAR`→`ALLOW_SPECIAL_70`; `NOT_SPECIAL_CHAR`→`SPECIAL_70` | Recipient address ≤70. |
| `ValidateTextFormatRecipientAddsBNT` | `SPECIAL_BAHTNET_70` | `TEXT_ONLY_ENG_BAHTNET70`: not `validateEngTextNumber`→`SPECIAL_BAHTNET_70` | BAHTNET address ≤70, English/num/`/`. |
| `ValidateTextFormatRemarkInv` | `REMARK_INV` | `NO_SPECIAL_CHAR`→`REMARK_INV` | Invoice remark ≤100. |
| `ValidateTextFormatRecipientTax` | *(literal)* `"The information in this field must be number and and not exceed 15 maximum length."` | `NO_SPECIAL_CHAR`→`SPECIAL_CHAR` | Tax ID ≤15 (note doubled "and and"; the `IsNumeric` alt is commented out — **special-char check only**, numeric-ness NOT enforced here). |
| `ValidateTextFormatPhoneNum` | *(literal)* `"…mobile number and not exceed 3 maximum mobile numbers."` | `PHONE_NUMBER`: comma-split, strip `-`, each must be numeric **and** exactly 10 digits → `PHONE` | Up to 3 phones. |
| `ValidateTextFormatIncomeDesc` | *(literal)* `"Income description is mandatory for type of income no. 6 and not exceed 80 maximum length."` | `NO_SPECIAL_CHAR`→`SPECIAL_CHAR` | WHT income-6 description ≤80. |
| `ValidateTextFormatDebit` | *(literal)* `"Debit account number must be a 10-digit number."` | `ACCOUNT_NUMBER`: not numeric→`Debit_error` | Debit acct (length via caller). |
| `ValidateTextFormatDebitFee` | *(literal)* `"Debit fee account number must be a 10-digit number."` | `ACCOUNT_NUMBER`: not numeric→`Debit_error` | Debit-fee acct. |
| `ValidateTextFormatCustomerBatchRef` | `TEXT_CUSTOMER_BATCH_REF` | `TEXT_ONLY_ENG`: if `validateTextNoPipe` OR `validateTextNoSquare` OR `validateTextNoTriangleSign` (contains `|`,`#`,`^`)→`TEXT_CUSTOMER_BATCH_REF` | Batch ref ≤12, no `| # ^`. |
| `ValidateTextFormatBahtNet` | `SPECIAL_BAHTNET_140` | `TEXT_ONLY_ENG_BAHTNET140`: not `validateEngTextBNT`→`SPECIAL_BAHTNET_140`; `NOT_SPECIAL_CHAR`: `validateTextWithSpecialChar`→`SPECIAL_70` | BAHTNET name ≤140. |

> **`ValidateTextFormatPhoneNum` quirk:** the per-phone length check is `ValidateTextFormat("NUMBER", str(aPhone), 10, 10)`. VBA `Str()` on a numeric value **prepends a leading space** for non-negatives and **drops a leading zero** (mobile numbers start with `0`), so `"0812345678"` → number `812345678` → `Str` → `" 812345678"` (len 10 but wrong content). The earlier raw `IsNumeric(aPhone)` guard is what actually rejects non-numerics; the `Str()` length path is fragile. Re-implementers should length-check the **raw** string.

---

### 8. Amount validators

Common gate at the top of each: reject if `""`, non-numeric, contains `","`, or has **>2 decimal places** (`AMOUNT_DECIMAL`). Value parsed with `CDec(strInput)` (into a `Double` var). `minLength`/`maxLength` params are **always overwritten** with defaults — callers cannot widen the floor.

| Function | Empty | Floor (min) | Ceiling (max, default) | Floor-fail | Ceiling-fail | Extra `Select Case`/notes |
|---|---|---|---|---|---|---|
| `ValidateAmount` | `PLEASE_ENTER` | `0.01` | `9,999,999,999,999.99` | *literal* "…must be number." | *literal* "…must not exceed 9,999,999,999,999.99…" | `AMOUNT`/`AMOUNT_CREDIT`/`WHTDeductRate` cases re-check negativity. **Dead branch:** the 2nd `ElseIf … WHTDeductRate` is unreachable (1st `ElseIf` already covers non-numeric/comma). |
| `ValidateAmountCredit` | `PLEASE_ENTER` | `0.01` | `9,999,999,999,999.99` | *literal* "…credit amount must be more than zero." | same ceiling literal | `AMOUNT_CREDIT` case; comma/non-numeric→`AMOUNT`. |
| `ValidateAmountPromptpay` | *(no empty branch)*→`AMOUNT` | `0.01`→`AMOUNT_CREDIT` | **`10,000`**→`PROMPTPAY_AMOUNT` | `AMOUNT_CREDIT` | `PROMPTPAY_AMOUNT` | E-wallet cap ฿10,000. |
| `ValidateAmountSmart` | →`AMOUNT` | `0.01`→`AMOUNT_CREDIT` | **`2,000,000`**→`SMART_AMOUNT` | `AMOUNT_CREDIT` | `SMART_AMOUNT` | SMART/ORFT/PromptPay cap ฿2M. |
| `ValidateAmountInvoiceAmount` | →`AMOUNT` | **`-9,999,999,999,999.99`** (negatives allowed!) | `9,999,999,999,999.99` | *literal* "…must be number." | ceiling literal | Invoice line may be **negative** (credit note). |
| `ValidateAmountWHTPercentage` | →`WHTDeductRate` | `0` | `9,999,999,999,999.99` | *literal* "…between 0 to 100" | *literal* "…between 0 to 100" | **BUG:** message says 0–100 but the max default is `9.99e12`, so values **>100 are NOT rejected**. `AMOUNT` case rechecks negativity→`WHTDeductRate`. |

> Every amount validator uses `InStr(strInput, ",")` as a boolean (nonzero position = truthy) → **any comma rejects**. Inputs must be raw, un-grouped decimals. Decimal-place rule: `Split(strInput,".")`; if `UBound>0` and the fractional part `Len > 2` → `AMOUNT_DECIMAL`.

---

### 9. Email validator

#### `IsEmailValid(email) As Boolean` (Variant param)
Hand-rolled RFC-ish check, returns `True` unless a rule fails:
- `Len(email) >= 6` and no spaces.
- **Exactly one** `@`: `Len(email) - Len(Replace(email,"@","")) = 1`.
- `atPos >= 2`; last dot `dotPos >= atPos+2`; dot not the final char.
- **Local part** chars ∈ `a–z A–Z 0–9 . _ + -` only.
- **Domain**: no `..` and no `--`; must not start with `-` or `.`; **TLD** (after last dot) `Len >= 2`.
- **Not enforced:** overall 100-char cap (despite the `EMAIL` message), domain body character-set, single-label domains.

---

### 10. Character-class predicates

#### `validateTextWithSpecialChar(text) As Boolean` → **True if a disallowed special char is present, or the string starts with a space**
```vba
specialChar = Array("!", """", "#", "$", "%", "&", "*", "+", ";", "<", "=", ">", "?", "@", "[", "\\", "]", "^", "_", "`", "{", "|", "}", "~", "\")
For Each sChar In specialChar
    If InStr(text, sChar) > 0 Or Mid(text, 1, 1) = " " Then checkValid = True: Exit For
Next
```
Disallowed set: `! " # $ % & * + ; < = > ? @ [ ] ^ _ ` { | } ~ \` (the `"\\"` array element = two backslashes, effectively redundant with the trailing single `"\"`). Leading space also fails. **Allowed** (not in set): `( ) - . / , ' :` and digits/letters.

#### Single-character predicates (all return `True` if the char is found)
| Function | Looks for |
|---|---|
| `validateTextNoPipe(txt)` | `|` |
| `validateTextNoSquare(txt)` | `#` |
| `validateTextNoTriangleSign(txt)` | `^` |
| `validateTextNoSpace(txt)` | `" "` (any space) |
| `validateTextCustomerBatch(txt)` | the literal 3-char substring `"|#^"` — **BUG:** searches for the contiguous string, not "any of the three"; essentially never fires. The real batch-ref check uses the three separate predicates instead. Contains leftover `Debug.Print` lines. **Dead/broken.** |

#### Whitelist predicates (lowercase input, reject leading space; return **True if every char is in the allowed set**)
| Function | Allowed set (after `LCase`) | Used for |
|---|---|---|
| `validateEngText` | `a–z` + space | `TEXT_ONLY_ENG`, `TEXT_ONLY_ENG_BAHTNET` |
| `validateEngTextBNT` | `a–z 0–9 - ' ( ) . , / ` + space | BAHTNET name ≤140 (`TEXT_ONLY_ENG_BAHTNET140`). Has a redundant inner `If txt = " "`. |
| `validateEngTextNumber` | `a–z 0–9 / ` + space | BAHTNET ≤70 (`TEXT_ONLY_ENG_BAHTNET70`) |
| `validateEngTextNumChar` | `a–z 0–9 ! @ # $ % ^ & * ( ) _ + ` + space | `TEXT_ONLY_ENG_140` |
| `validateEngTextNumSpecialChar` | `a–z 0–9 - ( ) : / ' , . | ^ \ # ` + space | `TEXT_ONLY_ENG_NUM_SPECIAL` — **note this ALLOWS `|`, `^`, `#`, `\`** (unlike the delimiter-safety rules elsewhere). |
| `validateEngTextNumSpecial` | `a–z 0–9 @ # & * ( ) _ . , / ' - ` + space | `NOTTHAI` → any char outside (e.g. Thai) → `NO_THAI` |

All six: `txt = LCase(txt)`; loop each char `If InStr(listOfEndChar, Mid(txt,Index,1)) = 0 Or Mid(txt,1,1) = " " Then checkEngExist = False: Exit For`. A **leading space fails** even if all chars are otherwise allowed.

---

### 11. Master-data list helpers

#### `InListObject(key, list As ListObject) As Boolean`
Loops `Index = 0 To list.ListRows.Count`, compares `list.DataBodyRange(Index,1).value = key`. **Off-by-one:** starts at `0` (invalid 1-based `DataBodyRange` index) and goes to `Count` inclusive → row 0 access and boundary quirks under `On Error`-free execution. Re-implementers should iterate `1..Count`.

#### `checkValueExistInDropDownList(key, table As String) As Boolean`
`Set tbMaster = Worksheets("Master_data").ListObjects(table)` then `InListObject(key, tbMaster)`.

---

### 12. Default-value helpers (blank → product sub-code)

| Function | Blank → |
|---|---|
| `checkDefaultValueSmartPayroll` | `"01"` |
| `checkDefaultValueSmartCredit` | `"04"` |
| `checkDefaultValueBahtNet` | `"00"` |
| `checkDefaultValuePayroll` | `"01"` |

Each: `If IsEmpty(value) Or value = "" Then <default> Else value`.

---

### 13. Sheet-level orchestration

#### `Sub VallidateAll()` (note the misspelling — this is the actual entry point name)
The "Validate" button handler:
```vba
lastRow = Worksheets("Payment").Cells(Rows.count, 1).End(xlUp).row
For r = idxHeader + 1 To lastRow          ' rows 9..last
    Worksheets("Payment").ValidateRowInfo (r)   ' Sheet1.ValidateRowInfo
Next r
validateSystemReferenceId
cbInvoice = Worksheets("Payment").CheckBoxes("InvoiceChk").value
If cbInvoice = 1 Then ValidateSheetByName "Invoice"
cbWht = Worksheets("Payment").CheckBoxes("WHTChk").value
If cbWht = 1 Then ValidateSheetByName "WHT"
```
- Payment credit rows validated via **`Sheet1.ValidateRowInfo`**; Invoice/WHT only when their checkbox = 1, via `ValidateSheetByName` → **`Sheet3`/`Sheet4.ValidateRowInfo`**.
- The old inline per-row loops for Invoice/WHT are present but **commented out**.

#### `Public Sub ValidateSheetByName(sheetname As String)`
```vba
lastRow = Worksheets(sheetname).Cells(Rows.count, 1).End(xlUp).row
For r = 2 To lastRow: Worksheets(sheetname).ValidateRowInfo (r): Next r
```
Invoice/WHT data starts at **row 2** (row 1 = header). Payment starts at `idxHeader+1`.

#### `Function validateSystemReferenceId()`
Validates `Payment!E6` (`addressSystemReferenceId`, from Util):
```vba
If validateTextNoSpace(systemReferenceId) Or validateTextWithSpecialChar(systemReferenceId) Or Len(systemReferenceId) > 18 Then
    InvalidCell rowSystemReferenceId, colSystemReferenceId, "ERROR_SYSTEM_REFERENCE_ID"
Else
    validCell rowSystemReferenceId, colSystemReferenceId
End If
```
`limitLength = 18`. Invalid if it **contains any space**, **contains a special char**, or **exceeds 18 chars**. This is the **only** validator in the module that directly paints cells (all others return strings for the sheet `ValidateRowInfo` to flag).

---

### 14. SCB account check-digit

#### `CheckScbDigit(ByVal AcctNo As String) As Boolean`
`On Error Resume Next` at top (errors → silently `False`). `Const sKeySCB = "432765432"` (9 weights). Algorithm:
1. `strChkAcct = Replace(Trim(AcctNo), "-", "")`. Require `Len = Len(sKeySCB)+1 = 10` and numeric.
2. For each of the first 9 digits `i`: `ir = digit(i) * weight(i)`; keep **last digit** of `ir` if two-digit → `AryR(i)`.
3. Sum `AryR(1..9)` → `j`; keep **last digit** of `j` → `k`.
4. `j = 10 - k`; keep **last digit** if two-digit.
5. Valid iff `Right(strChkAcct,1) = j` (the 10th digit equals the computed check digit).

```vba
j = Mid(strChkAcct, i, 1): k = Mid(sKeySCB, i, 1): ir = j * k
If Len(Trim(ir)) > 1 Then AryR(i) = Right(ir, 1) Else AryR(i) = ir
...
j = 10 - k
If Len(Trim(j)) > 1 Then j = Right(j, 1)
If Trim(Right(strChkAcct, 1)) = Trim(j) Then CheckScbDigit = True Else CheckScbDigit = False
```
Only SCB 10-digit accounts are accepted; anything else → `False`.

#### `checkLengthProxyType(str As String) As Integer`
**Empty stub** — no body, always returns `0`. Dead code.

---

### 15. Edge cases, bugs & re-implementer must-knows

1. **`SPECIAL` code has no `TBErrorMessage` row** → the `TEXT_ONLY_ENG_BAHTNET` case surfaces a raw `"SPECIAL"` comment. Likely a copy error.
2. **`ValidateAmountWHTPercentage` does not enforce ≤100** despite its message — max defaults to `9,999,999,999,999.99`. A percentage of 5000 passes.
3. **`ValidateAmount`'s 2nd `ElseIf … "WHTDeductRate"` is unreachable** (dead branch).
4. **`ValidateTextFormat` `ACCOUNT_NUMBER` merged case is unreachable** — the earlier standalone `ACCOUNT_NUMBER` case wins.
5. **`validateTextCustomerBatch` is broken** (searches contiguous `"|#^"`); the working batch-ref rule is the three separate predicates in `ValidateTextFormatCustomerBatchRef`.
6. **`InListObject` off-by-one** (`0..Count`).
7. **`ValidateTextFormatPhoneNum` uses `Str(aPhone)`** → leading-zero loss / leading space; rely on the raw `IsNumeric` guard, not the length path.
8. **`ValidateTextFormatRecipientTax` no longer checks numeric-ness** (the `IsNumeric` branch is commented out — only special-char + length remain), despite the "must be number" message.
9. **Two `compareDateWithCurrentDate`** functions (this module returns `String` and is the live one; `Util.bas`'s `Boolean` version is dead/commented).
10. **Amount `min/max` params are ignored** — every amount validator overwrites them with hard-coded limits. Product-specific caps: PromptPay ฿10,000; SMART/ORFT ฿2,000,000; generic/invoice ฿9,999,999,999,999.99; invoice allows negatives down to −9,999,999,999,999.99.
11. **Future-date rule** (`compareDateWithCurrentDate`): SPN/SPN2/SPN3/SCN require strictly-future value dates; all products reject past dates; both return a **literal** sentence (not a code).
12. **Empty input is "valid"** in every `ValidateTextFormat*` (except the amount validators, which treat blank as `PLEASE_ENTER`/`AMOUNT`). Mandatory-field enforcement is the sheet modules' job, using the `msgSelect`/`msgEnter`/`msgMan*` codes exposed here.
13. **Buddhist-era years:** all date parsing flows through `Util.convDate`→`calYear` (subtracts 543 when year > currentYear+400). Year field is 4 digits in `dd/mm/yyyy`.
14. **No `Option Explicit`; heavy `Debug.Print`** residue throughout. Several `errMsg` values are literal English strings that intentionally bypass `FindErrorMessage` (shown verbatim).
15. **Colour/flag semantics** (via Util): red `ColorIndex 3` = error (+comment, +N1 counter), yellow `27` = row-level warn, `2` = clean. `validCell` re-tints to yellow if the row anchor (col-1) is yellow.

**Key source files referenced:** `Validation.bas` (this module); flagging + address constants + `FindErrorMessage`/`convDate`/`calYear` in `Util.bas`; `ValidateRowInfo` per sheet in `Sheet1.bas` (Payment), `Sheet3.bas` (Invoice), `Sheet4.bas` (WHT); `delim="|"` in `Export.bas`; `CreditCode="TXNDET"` in `Sheet1.bas`; the message text data in `Master_data!TBErrorMessage` (`A301:B364`).


---

## SCB Business Net Toolkit — VBA Reference: `Sheet3.bas` (Invoice), `Export.bas`, `Clear.bas`

> Toolkit v1.3.8. None of these three modules declare `Option Explicit` — every undeclared identifier (`lastRow`, `IsValid`, `CountDuplicateRow`, `i`, `answer`, `ans`, `total`, `CountError`, etc.) is an implicit `Variant`. In `Clear.bas` (a standard module named `Clear`) every unqualified `Cells(...)`/`range(...)` binds to `ActiveSheet`, which the code assumes is **Payment** (the Clear/Retry buttons live there).

### Cross-module constants these files depend on (resolved from `Util.bas` / `Validation.bas`)

| Name | Value | Defined in | Meaning |
|---|---|---|---|
| `delim` | `"\|"` | `Export.bas` (Public) | field separator, whole toolkit |
| `HeaderCode` | `"HEADER"` | `Validation.bas` | HEADER record code |
| `idxHeader` | `8` | `Validation.bas` | Payment header row; credit rows start at `A9` |
| `idxHeaderInv` | `1` | `Sheet3.bas` | Invoice header row; data starts at row 2 |
| `pleaseSelect` | `"--Select--"` | `Validation.bas` | product-type dropdown placeholder |
| `defaultCustomerBatchRef` | `"MMDDYYHHMMSS"` | `Validation.bas` | placeholder text in the batch-ref cell |
| `msgSelect` | `"PLEASE_SELECT"` | `Validation.bas` | error-message KEY (looked up in `TBErrorMessage`) |
| `msgEnter` | `"PLEASE_ENTER"` | `Validation.bas` | error-message KEY |
| `TBInvoiceDetail` | `"TBInvoiceDetail"` | `Validation.bas` | (used only by dead code) |
| `TBCreditInfo` | `"TBCreditInfo"` | `Validation.bas` | (used only by dead code) |
| `addressCountError` | `"N1"` | `Util.bas` | Payment cell holding the running error count |
| `addressCustomFileRef` | `"C2"` | `Util.bas` | customer **file** reference |
| `addressDebitAcc` | `"C3"` | `Util.bas` | debit account |
| `addressDebitAccFee` | `"C4"` | `Util.bas` | debit fee account |
| `addressValueDate` | `"C5"` | `Util.bas` | value date |
| `addressCustomBatchRef` | `"E2"` | `Util.bas` | customer **batch** reference |
| `addressDropDownProductType` | `"E4"` | `Util.bas` | product-type dropdown |
| `addressSystemReferenceId` | `"E6"` | `Util.bas` | system reference id |
| `addressProductCodeForValidate` | `"M1"` | `Validation.bas` | resolved product code (e.g. `PAY`) |

**Helpers referenced (from `Util.bas`), with their real behavior:**

- `convertAmountFormat(v)` = `FormatNumber(v,2)` with commas stripped → `"1234.56"`. The trailing `Replace(removeCommar, "", "")` is a **no-op** (zero-length find string). No `.`-removal despite the module also owning a separate `removeDecimal`/`removePeriod`.
- `convertDateFormat(v)` → `"YYYYMMDD"`. Internally `convDate` parses `dd?mm?yyyy` and applies `calYear` (Buddhist→Gregorian: subtract 543 when `year > thisYear+400`), then `Format(...,"yyyymmdd")`, then re-applies `calYear` on the already-Gregorian year (idempotent). **Latent bug:** it re-inserts the year via `Replace(dateString, yearString, str(calDCyear))`; `Str()` prefixes a space (`" 2026"`) — the callers in `Sheet3`/`Export` wrap it in `Trim(...)`, which is the only reason the leading space doesn't survive. Because it replaces the year **substring** (not `Left/Mid` splice), a pathological `mmdd` that contains the year digits could double-substitute.
- `checkEmptyString(v)` → `""` if empty, else `convertAmountFormat(v)`.
- `CollectionToArray(c, StartIdx, Size)` → `Variant` array, 0-based by default (`StartIdx` omitted = 0).
- `FindErrorMessage(key)` → looks `key` up in `Master_data!TBErrorMessage` (col1=key, col2=text). Every `MsgBox FindErrorMessage("…")` below shows a Master_data-driven string.
- `generateCustomerBatchReferanceName()` = `Format(Now(), "DDMMYYHHMMSS")` (**DDMMYY**, note: differs from the `MMDDYYHHMMSS` placeholder constant).
- `validCell/InvalidCell/validRow/invalidRow/forceValidRow` = cell/row colorizers + comment setters (red `3` = invalid, `27` = invalid-row highlight, white `2` = valid).

---

## 1) `Sheet3.bas` — Invoice worksheet (code name `Sheet3`, tab `"Invoice"`)

### Module-level constants

```vba
Const InvoiceCode As String = "INVDET"

Const idxHeaderInv As Integer = 1
Const colRecordId As Integer = 1          'Record Identifier (col A)
Const colCreditSeqNo As Integer = 2       'Customer Transaction Reference (col B)
Const colInvoiceDate As Integer = 3       'Invoice Date (col C)
Const colInvoiceNo As Integer = 4         'Invoice Number (col D)
Const colInvoiceAmount As Integer = 5     'Invoice Amount (col E)
Const colInvoiceDes As Integer = 6        'Invoice Description (col F)
Const colPurchaseOrderNo As Integer = 7   '(col G)
Const colVATAmount As Integer = 8         '(col H)
Const colWHTAmount As Integer = 9         '(col I)
Const colInvoiceNetAmount As Integer = 10 'Invoice Net Amount (col J)
Const colRemarkForInvoice As Integer = 11 '(col K)

Const sheetname = "Invoice"               'implicit Variant (no As)
```

The sheet layout is **11 columns** A..K; column A holds the literal `"INVDET"` stamp, column B holds the parent credit-line's Customer Transaction Reference (the join key back to Payment).

#### `ExportInvoiceRow(r) As String` — THE INVDET LINE (10 fields, authoritative)

Builds a **10-element** array `rowArr(0..9)` joined by `delim`. **Field order does NOT match sheet column order** (PO number is pulled before Invoice Amount; description sits between amount and VAT).

```vba
ReDim rowArr(9)
rowArr(0) = "INVDET"                                        'hardcoded; colRecordId read is commented out
rowArr(1) = Trim(convertDateFormat(Me.Cells(r, colInvoiceDate).value))   'YYYYMMDD
rowArr(2) = Trim(Me.Cells(r, colInvoiceNo).value)
rowArr(3) = Trim(Me.Cells(r, colPurchaseOrderNo).value)
rowArr(4) = convertAmountFormat(Me.Cells(r, colInvoiceAmount).value)
rowArr(5) = Trim(Me.Cells(r, colInvoiceDes).value)
rowArr(6) = convertAmountFormat(Me.Cells(r, colVATAmount).value)
If Not IsEmpty(Me.Cells(r, colWHTAmount).value) Then
    rowArr(7) = checkEmptyString(Me.Cells(r, colWHTAmount).value)
Else
    rowArr(7) = "0.00"
End If
rowArr(8) = convertAmountFormat(Me.Cells(r, colInvoiceNetAmount).value)
rowArr(9) = Trim(Me.Cells(r, colRemarkForInvoice).value)
res = Join(rowArr, delim)
```

**Resulting INVDET layout (pipe-delimited):**

| # | Field | Source col | Format |
|---|---|---|---|
| 0 | Record id | — (literal) | `INVDET` |
| 1 | Invoice Date | C `colInvoiceDate` | `convertDateFormat` → `YYYYMMDD`, `Trim`med |
| 2 | Invoice No | D `colInvoiceNo` | `Trim` |
| 3 | Purchase Order No | G `colPurchaseOrderNo` | `Trim` |
| 4 | Invoice Amount | E `colInvoiceAmount` | `convertAmountFormat` → `nnn.nn` |
| 5 | Invoice Description | F `colInvoiceDes` | `Trim` |
| 6 | VAT Amount | H `colVATAmount` | `convertAmountFormat` |
| 7 | WHT Amount | I `colWHTAmount` | `checkEmptyString`; **defaults `"0.00"` when cell is empty** |
| 8 | Invoice Net Amount | J `colInvoiceNetAmount` | `convertAmountFormat` |
| 9 | Remark | K `colRemarkForInvoice` | `Trim` |

**WHT-default subtlety / edge cases:** the `IsEmpty` guard and `checkEmptyString` are redundant (both handle empty), but they diverge for a cell holding a literal empty string `""` or whitespace: `IsEmpty("")` is `False`, so `checkEmptyString(" ")` → `convertAmountFormat(" ")` → `FormatNumber` on non-numeric can raise a runtime error. A truly blank cell → `"0.00"`. Note this is the ONLY INVDET field with a non-empty default; every other empty cell exports as an empty field (`Trim("")=""`, `convertAmountFormat("")` will error on blanks though — export assumes mandatory numerics are filled, enforced by `ValidInvMandatory`).

#### `ExportData(ref As String) As String` — nesting driver (called by Payment/`Sheet1`)

```vba
lastRow = Me.Cells(Rows.count, 2).End(xlUp).row      'last non-empty in col B (credit-seq)
For r = 2 To lastRow
    If Me.Cells(r, colCreditSeqNo).value = ref Then
        'ValidateRowInfo (r)                          'NOTE: commented out — no re-validation at export
        data.Add ExportInvoiceRow(r)
    End If
Next r
If data.count > 0 Then
    resData = Join(CollectionToArray(data, 0, data.count), vbNewLine)
    ExportData = resData
End If
```

Returns `vbNewLine`-joined INVDET lines for **all Invoice rows whose col-B key equals `ref`** (the parent credit's Customer Transaction Reference), or `""` if none. This is how INVDET blocks get nested beneath their TXNDET. Iterates from row 2 (skips header). Does **not** re-validate.

### Event handlers

#### `Worksheet_SelectionChange(Target)`

```vba
If 1 < Target.Cells.count Then Exit Sub               'multi-cell selection ignored
If Not Intersect(Target, range("B1:C1")) Is Nothing Then
    Cancel = True                                     'DEAD: SelectionChange has no Cancel arg;
    Target.Offset(rowOffset:=1, columnOffset:=0).Select   'just nudges selection down a row
End If
If Target.row > idxHeaderInv And Target.Column = colCreditSeqNo Then
    lastRow = Worksheets("Payment").Cells(Rows.count, 1).End(xlUp).row
    If lastRow > idxHeader Then                        '>8 ⇒ Payment has credit rows
        With Target.Validation
        .Delete
        .Add Type:=xlValidateList, AlertStyle:=xlValidAlertStop, _
             Operator:=xlBetween, Formula1:="=Payment!A" & idxHeader + 1 & ":A" & lastRow
        .IgnoreBlank = True : .InCellDropdown = True : .ShowInput = True : .ShowError = True
        End With
    End If
End If
```

- Selecting header cells `B1:C1` bumps the cursor to row 2.
- Selecting any col-B cell below the header **dynamically installs a dropdown** listing the Payment credit-seq numbers `Payment!A9:A{lastRow}` — so an invoice row is bound to an existing payment line. `Cancel = True` is a dead assignment (undeclared variant; the event signature has no `Cancel`).

#### `Worksheet_Change(Target)`

```vba
If Target.row > idxHeaderInv Then
  Select Case Target.Column
  Case colCreditSeqNo
    If IsEmpty(Target.value) Then
        Me.Cells(Target.row, colRecordId).ClearContents      'clear col A
    Else
        Me.Cells(Target.row, colRecordId).value = InvoiceCode 'stamp "INVDET" in col A
    End If
  End Select
  'ValidateCell Target                                        'commented out
End If
```

Auto-stamps/clears the `INVDET` marker in column A whenever the credit-seq (col B) is set/cleared. The `OVERLIMIT_CREDIT` MsgBox path is commented out here.

### Validation functions

#### `ValidateCell(Target) As Integer`

`Me.Unprotect`; `On Error GoTo errorHandle`. Per-column dispatch (returns 1 = invalid, else colors cell valid):

| Column | Const | Rule invoked |
|---|---|---|
| B | `colCreditSeqNo` | `count = findDuplicateCreditSeqNo(value,"B:B")`; **`If count > 5`** → MsgBox `OVERLIMIT_CREDIT`, clear cell. (**Dead branch** — `findDuplicateCreditSeqNo` always returns 0, see below.) |
| C | `colInvoiceDate` | `ValidateTextFormat("DATE", value, 1, 10)` (only if non-empty) |
| D | `colInvoiceNo` | `ValidateTextFormat("NO_SPECIAL_CHAR", value, 1, 15)` |
| E | `colInvoiceAmount` | `ValidateAmountInvoiceAmount("AMOUNT", value, -9999999999999.99, 9999999999999.99)` |
| F | `colInvoiceDes` | `ValidateTextFormat("TEXT_NO_PIPE", value, 1, 100)` |
| G | `colPurchaseOrderNo` | `ValidateTextFormat("NO_SPECIAL_CHAR", value, 1, 30)` |
| H | `colVATAmount` | `ValidateAmountInvoiceAmount("AMOUNT", value, ±9999999999999.99)` |
| I | `colWHTAmount` | `ValidateAmountInvoiceAmount("AMOUNT", value, ±9999999999999.99)` |
| J | `colInvoiceNetAmount` | `ValidateAmountInvoiceAmount("AMOUNT", value, ±9999999999999.99)` |
| K | `colRemarkForInvoice` | `ValidateTextFormat("TEXT_NO_PIPE", value, 1, 100)` |

Field length limits (min,max): InvoiceNo 15, PO 30, Description 100, Remark 100. Amount bounds ±9,999,999,999,999.99. Numerous alternate rules are commented out (`NO_SPECIAL_CHAR` vs `TEXT_NO_PIPE` for description/PO, `ValidateAmount` vs `ValidateAmountInvoiceAmount`, `ValidateTextFormatRemarkInv`).

Tail logic:
```vba
errorHandle:
    Select Case Err.Number
    Case 13
        MsgBox "Successfully pasted all text."     'misleading text for a type-mismatch error
    End Select
If msg <> "" Then
    InvalidCell Target.row, Target.Column, msg, sheetname
    ValidateCell = 1
ElseIf Target.Interior.ColorIndex = 3 And IsEmpty(Target) Then   'still-red empty mandatory
    ValidateCell = 1
Else
    validCell Target.row, Target.Column, sheetname
End If
```
**Note:** the `errorHandle:` label is not guarded by an `Exit`/`Resume`, so normal (no-error) execution **falls through** it (`Err.Number = 0`, no match) into the msg check — it doubles as the normal continuation. On a real error mid-`Select Case`, remaining cases are skipped.

#### `ValidateEachCells(row) As Collection`
Loops `i = 1 To lastCol` (`lastCol = Cells(idxHeaderInv, Columns.count).End(xlToLeft).Column`), runs `ValidateCell(Cells(row,i))`, and returns the collection of failing column indices (`res > 0`).

#### `ValidateRowInfo(row)`
```vba
If IsEmpty(Cells(row, colCreditSeqNo)) Then forceValidRow sheetname, row : Exit Sub
IsValid = ValidInvMandatory(row)
Set failColList = ValidateEachCells(row)
If (failColList.count = 0) And IsValid Then validRow row, sheetname _
Else invalidRow row, failColList, sheetname
```
Empty credit-seq ⇒ row treated as blank/neutral (`forceValidRow`) and skipped. Otherwise combine mandatory-check + per-cell-check.

#### `ValidInvMandatory(row) As Boolean`
Mandatory (non-empty) fields, each `InvalidCell(... msgEnter ...)` on failure: **`colCreditSeqNo`, `colInvoiceDate`, `colInvoiceNo`, `colInvoiceAmount`, `colVATAmount`, `colInvoiceNetAmount`**. NOT mandatory: description, purchase-order, WHT amount, remark. Quirk: the `colCreditSeqNo` empty case sets `False` but its `InvalidCell` is commented — no red mark, just a silent fail.

#### `findDuplicateCreditSeqNo(key, range) As Integer` — caps invoices per credit line at 5
```vba
lastRow = Worksheets("Invoice").Cells(Rows.count, 1).End(xlUp).row
For curRow = firstRow To lastRow                       'firstRow Const = 2
    If Cells(curRow, colCreditSeqNo).value = key Then
        CountDuplicateRow = CountDuplicateRow + 1       'CountDuplicateRow is UNDECLARED
        If CountDuplicateRow > 5 Then
            MsgBox "The system support maximum 5 invoice details per credit line."
            Cells(curRow, colCreditSeqNo).value = ""    'blanks the 6th offender
            Exit Function
        End If
    End If
Next curRow
findDuplicateCreditSeqNo = 0                            'ALWAYS returns 0
```
Enforces **max 5 INVDET per credit line**. The `range` parameter is ignored (column hardcoded via `colCreditSeqNo`). Return value is always 0, so the `count > 5` guard in `ValidateCell` is dead — the cap is actually enforced by the internal MsgBox+blank side-effect.

### Dead / legacy code in `Sheet3.bas`

`UpdateCredit(row)` and `UpdateCreditWithInvoice(key, totalInvoice, totalInvoiceAmount, totalVatAmount)` roll invoice totals back into a **`Credit_Info`** sheet's `TBCreditInfo` table using constants `colTotalInvoiceDetail`, `colTotalInvoiceAmount`, `colTotalVatAmount` **that are not defined in any extracted module**, and a `Credit_Info` sheet that isn't among the 6 workbook sheets. Nothing calls them. They would raise at runtime if invoked — treat as vestigial from an earlier post-pay/aggregation design.

---

## 2) `Export.bas` — top-level export orchestration

### Module constants
```vba
Public Const delim As String = "|"       'toolkit-wide field separator
Const colCreditAmount As Integer = 5      'Payment col E = credit amount (used by TRAILR total)
```

### `Public Sub Export()` — full flow, in order

**Gate sequence (any gate `Exit Sub`s):**

1. Read `lastRowCredit = Payment!A{last}`; scratch reads `dubSeqNo=A1`, `creditSeqNo=A9`.
2. **`retry`** (from `Clear.bas`) — resets `N1=0`, clears colors/comments, and re-runs `VallidateAll` + `ValidateDebit` so error state is fresh.
3. **Auto-gen batch ref if empty:**
   ```vba
   If IsEmpty(Worksheets("Payment").range(addressCustomBatchRef)) Or Worksheets("Payment").range(addressCustomBatchRef).value = "" Then
       Worksheets("Payment").range(addressCustomBatchRef).value = generateCustomerBatchReferanceName   'E2 = DDMMYYHHMMSS
   ```
4. **No-credit gate:** `If lastRowCredit < 9 Then MsgBox FindErrorMessage("NO_CREDIT_SEQ_NO") : Exit Sub` (rows start at 9, so `<9` means zero recipients).
5. **Validation-error gate:** `CountError = Payment!N1`; `If CInt(CountError) > 0 Then MsgBox FindErrorMessage("EXPORT_ERROR") : Exit Sub`.
6. **Invoice/WHT checkbox↔data matrix:** `answer = validateInvoiceAndWHT()`; `If answer = vbNo Then Exit Sub` (see full matrix below).
7. Declare locals + `Const adSaveCreateOverWrite = 2`, `adTypeBinary = 1`, `adTypeText = 2`.
8. `FileName = generateCustomerFileReferanceName()` (suggested save-as name).
9. Read `customerFileRef = C2`, `customerBatchRef = E2` (**read but never used — dead var**), `customerSystemReferenceId = E6`. `crcTxt = ""`.
10. **Payroll / pure-payment force-hide** (runs *after* step 6):
    ```vba
    Select Case Worksheets("Payment").range(addressProductCodeForValidate).value   'M1
        Case "PAY", "PA2", "PA3", "SPN", "SPS", "SPN2", "SPS2", "SPN3", "SPS3"
            Worksheets("Invoice").Visible = False
            ActiveSheet.CheckBoxes("InvoiceChk").value = Null
            ActiveSheet.CheckBoxes("InvoiceChk").value = False
            Worksheets("WHT").Visible = False
            ActiveSheet.CheckBoxes("WHTChk").value = Null
            ActiveSheet.CheckBoxes("WHTChk").value = False
    End Select
    ```
    For these 9 product codes (payment/payroll, no e-Invoice/e-WHT), Invoice & WHT sheets are hidden and both checkboxes force-cleared (the `= Null` then `= False` is a two-step reset to clear a possibly-grayed state). **Ordering note:** this runs *after* `validateInvoiceAndWHT()`, so for a `PAY` product with the Invoice box ticked-but-empty, the export would already have been blocked at step 6 before the force-off could suppress it.
11. `creditSeqNo = Payment.CheckCreditSeqNoBeforExport()` and `dubSeqNo = Payment.FindDuplicatesInColumn()` (side-effecting validators in `Sheet1`; return values discarded here).
12. `ans = MsgBox("Do you want to generate text file for upload? ", vbYesNo)`; only on `vbYes`:
13. `fileSaveName = Application.GetSaveAsFilename(InitialFileName:=FileName, fileFilter:="Text Files (*.txt), *.txt")`; only if `<> False`:

#### File assembly (the exact HEADER / body / TRAILR)

```vba
'Header
csvTxt = csvTxt & HeaderCode & delim & customerFileRef & delim & customerSystemReferenceId & vbNewLine
'Batch Details  (BCHDET + TXNDET + nested INVDET/WHTCER all come from Sheet1.ExportData)
csvTxt = csvTxt & Worksheets("Payment").ExportData() & vbNewLine

Dim total As Collection
Set total = CountTotalRecord()
'Trailr
csvTxt = csvTxt & "TRAILR" & delim & total.item(1) & delim & total.item(2) & delim & convertAmountFormat(str(total.item(3)))
```

- **HEADER line:** `HEADER|{C2 customerFileRef}|{E6 systemReferenceId}` + newline.
- **Body:** `Worksheets("Payment").ExportData()` — the BCHDET(10-field debit) + all TXNDET(28-field) rows, with INVDET/WHTCER nested — is produced entirely by **`Sheet1` (Payment)**, not here. `Export.bas` only frames HEADER + TRAILR around it.
- **TRAILR line (no trailing newline):** `TRAILR|{item1}|{item2}|{item3-amount}` = `TRAILR|1|{creditCount}|{totalAmount}`.

#### `CountTotalRecord() As Collection`
```vba
lastRow = Worksheets("Payment").Cells(Rows.count, 1).End(xlUp).row
For i = idxHeader + 1 To lastRow            '9..lastRow
    totalCredit = totalCredit + 1
    totalAmount = totalAmount + Worksheets("Payment").Cells(i, colCreditAmount).value  'col E
Next i
returnModel.Add 1               'item(1) = TotalDebit  (HARDCODED 1)
returnModel.Add totalCredit     'item(2) = credit/recipient count
returnModel.Add totalAmount     'item(3) = Σ credit amounts
```
- `item(1)` (debit count) is **hardcoded 1** — the toolkit always emits a single debit.
- The per-row `If Not IsEmpty(creditSeq)` guard is **commented out**, so **every row from 9..lastRow is counted unconditionally**, including any interior blank row (trailing blanks are excluded because `lastRow` is the last non-empty col-A row). 
- `totalCredit` is an `Integer` → overflow (>32,767 recipients). `totalAmount` is `Double`.
- In TRAILR, `convertAmountFormat(str(total.item(3)))` formats to 2dp, commas stripped (`str()`'s leading space is harmless to `FormatNumber`).

#### UTF-8 **without BOM** write (ADODB.Stream double-stream idiom)
`hashed` is declared but **never assigned** ⇒ `""`; `crcTxt = ""`. So `hashed & crcTxt & csvTxt` == `csvTxt`.
```vba
Dim objStreamUTF8:      Set objStreamUTF8 = CreateObject("ADODB.Stream")
Dim objStreamUTF8NoBOM: Set objStreamUTF8NoBOM = CreateObject("ADODB.Stream")

With objStreamUTF8
  .Charset = "UTF-8"
  .Open
  .WriteText hashed & crcTxt & csvTxt          'text, UTF-8 (writes a 3-byte BOM)
  .position = 0
  .SaveToFile fileSaveName, adSaveCreateOverWrite   '=2  (this first save is redundant, overwritten below)
  .Type = adTypeText                           '=2
  .position = 3                                'skip EF BB BF (UTF-8 BOM)
End With

With objStreamUTF8NoBOM
  .Type = adTypeBinary                         '=1
  .Open
  objStreamUTF8.CopyTo objStreamUTF8NoBOM      'copies from byte offset 3 → drops the BOM
  .SaveToFile fileSaveName, adSaveCreateOverWrite   'final output = UTF-8 WITHOUT BOM
End With

objStreamUTF8.Close
objStreamUTF8NoBOM.Close
```
Mechanism: write UTF-8 text (BOM included) → seek to byte 3 → `CopyTo` a binary stream (copies only from the current position to EOF) → re-save. Net output is **UTF-8 without BOM**. The first `SaveToFile` (line 130) is functionally unnecessary (immediately overwritten at 139) but harmless. `starting_ws.Activate` restores the originally-active sheet before writing.

#### `generateCustomerFileReferanceName() As String`
```vba
If Payment!E2 = defaultCustomerBatchRef Or IsEmpty(Payment!E2) Or Payment!E2 = "" Then
    formatFileName = Format(Now(), "DDMMYYHHMMSS")
    Payment!E2 = formatFileName                                    'set batch ref
    Payment!C2 = Payment!E2 & Payment!M1                           'fileRef = batchRef & productCode
Else
    formatFileName = Payment!C2                                    'addressCustomFileRef
    FileNameExport = Left(formatFileName, 12)
End If
generateCustomerFileReferanceName = "SCB_file_reference_" & FileNameExport
```
**Bug:** in the *IF* branch, `FileNameExport` is **never assigned** ⇒ the returned name is `"SCB_file_reference_"` with an empty suffix. In practice `Export()` step 3 has already populated `E2` with a real timestamp before this runs, so the *ELSE* branch is normally taken — but it then reads `C2` (`addressCustomFileRef`), which step 3 does **not** set; if `C2` is blank, `Left("",12) = ""` and you again get `"SCB_file_reference_"`. Only affects the suggested save-as filename, not file content. `Left(...,12)` truncates the file-ref to 12 chars for the filename.

#### `validateInvoiceAndWHT() As Integer` — full checkbox↔data matrix
```vba
cbInvoice = Payment.CheckBoxes("InvoiceChk").value        '1 = checked, else unchecked (xlOff)
cbWht     = Payment.CheckBoxes("WHTChk").value
lastRowInvoice = Worksheets("Invoice").Cells(Rows.count, 2).End(xlUp).row   '1 = header only (no data)
lastRowWHT     = Worksheets("WHT").Cells(Rows.count, 2).End(xlUp).row
```
Evaluated **top-down**; first match wins:

| # | Condition | Meaning | Action |
|---|---|---|---|
| 1 | `cbInvoice=1 AND lastRowInvoice=1 AND cbWht=1 AND lastRowWHT=1` | both boxes checked, both empty | MsgBox `EXPORT_INVOICE_WHT_NULL` (title `EXPORT_WORNING`); `answer=vbNo` (**hard block**) |
| 2 | `cbInvoice=1 AND lastRowInvoice=1` | invoice checked, empty | MsgBox `EXPORT_INVOICE_NULL`; `vbNo` |
| 3 | `cbWht=1 AND lastRowWHT=1` | WHT checked, empty | MsgBox `EXPORT_WHT_NULL`; `vbNo` |
| 4 | `cbInvoice<>1 AND lastRowInvoice>1 AND cbWht<>1 AND lastRowWHT>1` | both have data, both unchecked | `answer = MsgBox(EXPORT_UNCHECK_INVOICE_WHT, vbQuestion+vbYesNo+vbDefaultButton2, …)` (user chooses; default = No) |
| 5 | `cbInvoice<>1 AND lastRowInvoice>1` | invoice data, unchecked | `MsgBox EXPORT_UNCHECK_INVOICE` (Yes/No, default No) |
| 6 | `cbWht<>1 AND lastRowWHT>1` | WHT data, unchecked | `MsgBox EXPORT_UNCHECK_WHT` (Yes/No, default No) |
| 7 | else | consistent | `answer = vbYes` |

Semantics: **checked-but-empty (rows 1-3) is a fatal `vbNo` block**; **has-data-but-unchecked (rows 4-6) is a Yes/No warning** (proceed drops that section from the file since Sheet1's nesting only fires when the box is checked). Because it's top-down, a checked-empty error masks a simultaneous unchecked-with-data warning on the other section (e.g. Invoice checked+empty + WHT data+unchecked → row 2 fires, blocks; WHT case never surfaced). `lastRow* = 1` ⇔ header-only ⇔ no data rows. All titles/messages come from `Master_data!TBErrorMessage`.

### Dead / commented code in `Export.bas`
- **`Public Function SHA256(sIn, Optional bB64)`** — fully commented out. Would use `System.Security.Cryptography.SHA256Managed` (+ `System.Text.UTF8Encoding`) via late binding, returning hex or Base64. Callers `ConvToHexString`/`ConvToBase64String` (also commented) use `MSXML2.DOMDocument` `bin.hex`/`bin.base64` node typing. Line 111 `'hashed = SHA256(csvTxt)` is commented; the earlier alternate ADODB write block (lines 113-118, writing `hashed & crcTxt & vbNewLine & csvTxt`) is commented. Net: no hash/CRC is emitted — `hashed`/`crcTxt` are empty.
- **`removeDecimal(value) As String`** — computes `Replace(value, ".", "")` into a local `removeDec` but **never assigns the return value** (returns `""`); also unused. Dead.

---

## 3) `Clear.bas` — reset / clear-form logic

Standard module `Clear`; unqualified `Cells/range` target `ActiveSheet` (assumed **Payment**). Color index legend used here: `2` = white (cleared/valid), `3` = red (invalid), `15` = gray-25% (highlight the debit input cells during clear).

#### `Public Sub clear()` — "Clear All" (full form reset, confirmed)
```vba
Cells(2, 3).Interior.ColorIndex = 15                    'gray C2
lastCell = Worksheets("Payment").range("A1").SpecialCells(xlCellTypeLastCell).Address
question = MsgBox(FindErrorMessage("CLEAR_ALL_CONFIRM"), vbQuestion + vbYesNo)
If question = vbYes Then
    'credit rows A9:lastCell → white, wipe contents+comments
    Worksheets("Payment").range("A" & idxHeader + 1 & ":" & lastCell).Interior.ColorIndex = 2
    Worksheets("Payment").range("A" & idxHeader + 1 & ":" & lastCell).ClearContents
    Worksheets("Payment").range("A" & idxHeader + 1 & ":" & lastCell).ClearComments
    Worksheets("Payment").range("C2:C6").ClearComments
    Worksheets("Payment").range(addressDropDownProductType).ClearComments      'E4
    Worksheets("Payment").range(addressCountError).value = 0                   'N1 = 0
    'debit-area cell backgrounds → white  (C3, C4, E4, F4, C5)
    Cells(3, 3).Interior.ColorIndex = 2
    Cells(4, 3).Interior.ColorIndex = 2
    Cells(4, 5).Interior.ColorIndex = 2
    Cells(4, 6).Interior.ColorIndex = 2
    Cells(5, 3).Interior.ColorIndex = 2
    Worksheets("Payment").range(addressCustomFileRef).ClearContents            'C2
    Worksheets("Payment").range(addressDebitAcc).ClearContents                 'C3
    Worksheets("Payment").range(addressDebitAccFee).ClearContents              'C4
    Worksheets("Payment").range(addressCustomBatchRef).value = ""             'E2
    Worksheets("Payment").range(addressValueDate).value = ""                  'C5
    Worksheets("Payment").range(addressDropDownProductType).value = pleaseSelect '"--Select--"
    Worksheets("Payment").CheckBoxes("WHTChk").value = False
    Worksheets("Payment").CheckBoxes("InvoiceChk").value = False
    Worksheets("Invoice").Visible = False
    Worksheets("WHT").Visible = False
    clearValidate "Invoice", True                        'wipe Invoice contents+colors+comments
    clearValidate "WHT", True                            'wipe WHT   contents+colors+comments
    Worksheets("Payment").range(addressSystemReferenceId).ClearContents        'E6
    Worksheets("Payment").range(addressSystemReferenceId).ClearComments
    Worksheets("Payment").range(addressSystemReferenceId).Interior.ColorIndex = 2
    clearAllListValidations "Payment"                    'strip list-validations except product dropdown
End If
```
Resets: all credit rows, debit header fields (C2/C3/C4/C5), batch ref (E2), value date (C5), product type → placeholder, both checkboxes off, hides Invoice/WHT, wipes Invoice & WHT sheets, resets system-ref (E6) and error count (N1=0), and removes ad-hoc list validations. Note `Cells(4,6)` = **F4** is reset white here but F4 has no named-address constant.

#### `Public Sub ClearCredit()` — clear only recipient rows (confirmed)
```vba
Cells(2, 3).Interior.ColorIndex = 15     'gray C2
Cells(2, 5).Interior.ColorIndex = 15     'gray E2
Cells(2, 6).Interior.ColorIndex = 15     'gray F2
lastCell = Payment!A1.SpecialCells(xlCellTypeLastCell).Address
question = MsgBox(FindErrorMessage("CLEAR_CREDIT_CONFIRM"), vbQuestion + vbYesNo)
If question = vbYes Then
    Payment!A9:lastCell .Interior.ColorIndex = 2
    Payment!A9:lastCell .ClearContents
    Payment!A9:lastCell .ClearComments
    Payment!N1 = 0
End If
```
Wipes the credit/recipient grid only (keeps debit header, batch ref, product type, Invoice/WHT). Resets error count.

#### `Public Sub retry()` — pre-export soft reset (called first thing in `Export()`)
```vba
Payment!N1 = 0
lastCell = Payment!A1.SpecialCells(xlCellTypeLastCell).Address
Payment!A9:lastCell .Interior.ColorIndex = 2          'white
Payment!A9:lastCell .ClearComments                    '← ClearComments only (KEEPS data)
'debit fields: clear comments + white (C2,C3,C4,E2,C5,E4)
Payment(addressCustomFileRef / addressDebitAcc / addressDebitAccFee / addressCustomBatchRef / addressValueDate / addressDropDownProductType).ClearComments
… .Interior.ColorIndex = 2
'system ref
Payment!E6 .ClearComments : Payment!E6 .Interior.ColorIndex = 2
clearValidate "Invoice"                               'no 'clear' flag ⇒ colors+comments only, KEEPS data
clearValidate "WHT"
VallidateAll                                          're-validate whole book (sets N1 via InvalidCell)
Worksheets("Payment").ValidateDebit
```
Distinct from `clear`: **does not wipe any data** — only clears prior error highlighting/comments and re-runs validation so `N1` (error count) is recomputed fresh. This is why `Export()` reads `N1` immediately after calling `retry`.

#### `Public Sub clearValidate(sheetname As String, Optional clear As Boolean)`
```vba
lastCell = Worksheets(sheetname).range("A1").SpecialCells(xlCellTypeLastCell).Address
Worksheets(sheetname).range("A2" & ":" & lastCell).Interior.ColorIndex = 2   'white
Worksheets(sheetname).range("A2" & ":" & lastCell).ClearComments
If clear Then Worksheets(sheetname).range("A2" & ":" & lastCell).ClearContents
```
Generic sheet reset for **Invoice/WHT** (data region `A2:lastCell`, header row 1 preserved). `Optional clear` defaults `False` ⇒ colors+comments only; `True` also wipes contents. Callers: `clear` uses `True` (destructive), `retry` uses default `False` (non-destructive).

#### `Public Sub clearAllListValidations(Optional sheetname As String)`
```vba
Set ws = getActiveSheet(sheetname)                    'sheetname="" ⇒ "Payment"
For Each cell In ws.UsedRange
    If F_cellHasValidation(cell) = True Then
        If cell.Validation.Type = xlValidateList Then
            If ws.Name = "Payment" Then
                If Not Replace(cell.Address, "$", "") = addressDropDownProductType Then  '"E4"
                    cell.Validation.Delete
                End If
            Else
                cell.Validation.Delete
            End If
        End If
    End If
Next
```
Removes every **list** data-validation across the sheet's `UsedRange`, **preserving the product-type dropdown at E4** on the Payment sheet (all list validations removed unconditionally on other sheets). `F_cellHasValidation` (Validation.bas) probes `cell.Validation.Type` under `On Error Resume Next` — returns `False` if the cell has no validation. `getActiveSheet("")` defaults to `"Payment"`. The `validationCount` bookkeeping is commented out.

---

### Re-implementer cheat-sheet (these 3 files)

- **Record framing lives in `Export.Export()`**: `HEADER|{C2}|{E6}` · newline · `{Sheet1.ExportData()}` (BCHDET+TXNDET+nested) · newline · `TRAILR|1|{creditCount}|{ΣcolE-amount}` — no trailing newline, no hash/CRC (SHA256 path is commented out). Output is UTF-8 **without BOM** via the two-`ADODB.Stream` `CopyTo`-from-offset-3 trick.
- **INVDET line built in `Sheet3.ExportInvoiceRow`** = 10 fields, order `INVDET | date(YYYYMMDD) | invNo | PONo | invAmt | desc | vatAmt | whtAmt(default "0.00") | netAmt | remark`. Field order ≠ column order. Nested per credit-line by matching Invoice col-B to the parent's Customer Transaction Reference.
- **Amounts** `= FormatNumber(x,2)` comma-stripped (`nnn.nn`); **dates** `= YYYYMMDD` with พ.ศ.→ค.ศ. `-543` correction; both wrapped in `Trim`.
- **Limits:** ≤5 invoices per credit line; invoice mandatory = {creditSeq, date, no, amount, VAT, netAmount}; amount bounds ±9,999,999,999,999.99; string caps invNo15/PO30/desc100/remark100.
- **Product codes `PAY,PA2,PA3,SPN,SPS,SPN2,SPS2,SPN3,SPS3`** force Invoice+WHT hidden & unchecked at export.
- **Gates before write:** no-credit (`<9`), `N1` error count `>0`, and the 7-branch `validateInvoiceAndWHT` matrix.
- **Known defects/quirks:** `generateCustomerFileReferanceName` can yield `"SCB_file_reference_"` with empty suffix; `CountTotalRecord` counts interior blank rows and uses `Integer` (overflow >32767); `convertDateFormat` year-substring `Replace` is fragile (saved only by `Trim`); `findDuplicateCreditSeqNo` always returns 0 (its `>5` caller-guard is dead; the cap is enforced by its own side effect); `UpdateCredit`/`UpdateCreditWithInvoice` reference a nonexistent `Credit_Info` sheet + undefined column consts (dead); `errorHandle` label falls through on the happy path and shows "Successfully pasted all text." on a type-mismatch; `customerBatchRef`/`removeDecimal` dead; no `Option Explicit` anywhere (all Variants).


---

## `Sheet1.bas` — Payment Sheet Code Module (CORE)

**VBA code name:** `Sheet1` · **Worksheet name:** `"Payment"` (sheet 2 in the workbook) · **~1444 lines.**
This module owns: the header/debit input area (rows 2–6), the credit-recipient grid (row 9 downward, header row = 8), all cell-level validation dispatch, the product-selection cascade (radio buttons → product tables → column show/hide → dropdown re-population), the Invoice/WHT checkbox gating, and **the export builders that emit `BCHDET` (debit) + `TXNDET` (credit) records** into the pipe-delimited upload file.

> **No `Option Explicit`.** Almost every working variable (`Var`, `tableList`, `lastRow`, `lastRowDropDown`, `prodCode`, `seqNo`, `BankCode`, `IsValid`, `islnvalid`, `i`, `r`…) is an **implicit `Variant`**. A re-implementer must treat these as loosely-typed.

---

### 1. Module-level Constants

#### 1.1 Record code (this module)
| Const | Value | Notes |
|---|---|---|
| `CreditCode` | `"TXNDET"` | Record identifier for a credit (recipient) row. Field 0 of every `TXNDET`. |

#### 1.2 Header/debit-area **row** indices — **ALL DEAD** (declared, referenced 0× beyond declaration)
| Const | Value | Intended meaning |
|---|---|---|
| `rowFileName` | `2` | Export Path & Filename |
| `rowBatchRef` | `2` | Batch Ref |
| `rowDebitAccountNo` | `4` | Debit Account No. |
| `rowFeeDebitAccountNo` | `5` | Fee Debit Account No. |
| `rowValueDate` | `6` | (comment says "Company Name" — stale comment) |

#### 1.3 Credit-grid **column** indices — the visible input columns (1-based)
| Const | Value | Column (letter) | Field |
|---|---|---|---|
| `colSeqNo` | `1` | A | Credit Seq No (auto-generated) |
| `colCreditSeqNo` | `1` | A | alias of colSeqNo (same column) |
| `colBank` | `2` | B | Bank (dropdown, display name) |
| `colCreditAccNo` | `3` | C | Credit Account No. / proxy |
| `colRecipientName` | `4` | D | Recipient name |
| `colAmount` | `5` | E | Amount |
| `colCustomerTransacRef` | `6` | F | Customer transaction ref |
| `colFeeCharge` | `7` | G | Fee charge (dropdown) |
| `colBranchCode` | `8` | H | Branch code (4 digits) |
| `colServiceType` | `9` | I | Service type (dropdown) |
| `colSMSNoti` | `10` | J | SMS notify phone number(s) |
| `colEmailNoti` | `11` | K | Email notify address |
| `colPaymentAdviceRemark` | `12` | L | Payment advice remark |

#### 1.4 Credit-grid **hidden "resolved code"** columns (13–20)
These are written by validation as it resolves dropdown display-values → codes; the export reads them.
| Const | Value | Column | Field |
|---|---|---|---|
| `colProductTypeCode` | `13` | M | Product code per row (=`M1`) |
| `colBankCode` | `14` | N | Resolved bank clearing code |
| `colFeeChargeCode` | `15` | O | Resolved fee-charge code |
| `colServiceTypeCode` | `16` | P | Resolved service-type code |
| `colNotiSMSFlag` | `17` | Q | `Y`/`N` SMS flag |
| `colNotiEmailFlag` | `18` | R | `Y`/`N` email flag |
| `colPaymentAdviceRemarkFlag` | `19` | S | `Y`/`N` |
| `colProxyTypeCode` | `20` | T | PromptPay proxy type (`EWL`/`NAT`/`MOB`/`TAX`) |

#### 1.5 Named-cell address constants (Payment sheet)
| Const | Value (cell) | Holds |
|---|---|---|
| `selectProduct` | `"E2"` | **DEAD** (declared, referenced 0×). Note: `E2` collides with `addressCustomBatchRef`. |
| `addressProductTable` | `"M2"` | current product-picklist table name (e.g. `TBPPPayroll`) |
| `addressBankTable` | `"N2"` | current bank-dropdown table name |
| `addressFeeTable` | `"O2"` | current fee-dropdown table name |
| `addressServiceTypeTable` | `"P2"` | current service-type-dropdown table name |
| `addressProductCode` | `"M1"` | the active **product code** (`PAY`,`PPY`,`BNT`,`SPN`…) — read all over |
| `colDropDownProduct` | `4` | **DEAD.** Declared `As String` but assigned numeric `4` (type-mismatch smell). |

#### 1.6 Flag literals
| Const | Value |
|---|---|
| `FLAG_Y` | `"Y"` |
| `FLAG_N` | `"N"` |

#### 1.7 `BCHDET`/batch header column indices — **ALL DEAD** (declared, referenced 0× beyond declaration)
Documentation-only mapping of the `BCHDET` layout; the actual `ExportDebitRow` hard-codes `rowArr(0..9)`.
| Const | Value | `BCHDET` field |
|---|---|---|
| `colRecordId` | `1` | Record Identifier |
| `colBatchRef` | `2` | Customer Batch Reference |
| `colProduct` | `3` | Product Code |
| `colProductCode` | `4` | Code of Product |
| `colValueDate` | `5` | Value Date |
| `colDebitAccountNo` | `6` | Debit Account No. |
| `colFeeDebitAccountNo` | `7` | Fee Debit Account No. |
| `colTotalDebitAmount` | `8` | Total Debit Amount |
| `colTotalCredits` | `9` | Total No. of Credits |
| `colDebitNote` | `10` | Internal Debit Note |
| `colPaymentRemark` | `11` | Payment Advice Remark (batch level) |

#### 1.8 Module-level `Dim` (module-scope Variants)
```vba
'Dim productTable As String   '<-- commented out
Dim bankTable As String
Dim feeTable As String
Dim ProductCode As String
```

#### 1.9 Constants/globals it depends on from **other modules** (needed to re-implement)
| Symbol | Value | Defined in |
|---|---|---|
| `delim` | `"|"` | Export.bas (`Public`) |
| `DebitCode` | `"BCHDET"` | Validation.bas |
| `idxHeader` | `8` | Validation.bas — **header row; records start at row 9** |
| `pleaseSelect` | `"--Select--"` | Validation.bas |
| `msgSelect` | `"PLEASE_SELECT"` | Validation.bas (error key) |
| `msgEnter` | `"PLEASE_ENTER"` | Validation.bas (error key) |
| `addressProductCodeForValidate` | `"M1"` | Validation.bas (same cell as `addressProductCode`) |
| `addressCountError` | `"N1"` | Util.bas |
| `addressCustomFileRef` | `"C2"` | Util.bas |
| `addressDebitAcc` | `"C3"` | Util.bas |
| `addressDebitAccFee` | `"C4"` | Util.bas |
| `addressValueDate` | `"C5"` | Util.bas |
| `addressCustomBatchRef` | `"E2"` | Util.bas |
| `addressDropDownProductType` | `"E4"` | Util.bas (the product picklist cell) |
| `addressSystemReferenceId` | `"E6"` | Util.bas |

---

### 2. Field-order arrays (quote exactly — the wire format)

#### 2.1 `BCHDET` — 10 fields (`ExportDebitRow`, `ReDim rowArr(9)`)
```vba
rowArr(0) = DebitCode                                          '"BCHDET"
rowArr(1) = Me.range(addressCustomBatchRef).value             'E2  batchRef
rowArr(2) = Me.range(addressProductCode).value                'M1  productCode
rowArr(3) = Trim(convertDateFormat(Me.range(addressValueDate).value)) 'C5 -> YYYYMMDD
rowArr(4) = Trim(Me.range(addressDebitAcc).value)             'C3  debitAcc
rowArr(5) = Trim(Me.range(addressDebitAccFee).value)          'C4  feeDebitAcc
rowArr(6) = convertAmountFormat(str(totalDebitAmount))        'sum of colAmount
rowArr(7) = totalCredits                                      'count of credit rows
rowArr(8) = ""                                                'internal debit note
rowArr(9) = ""                                                'payment advice remark (batch level)
res = Join(rowArr, delim)
```

#### 2.2 `TXNDET` — 28 fields (`ExportCreditRow(r)`, `ReDim rowArr(27)`)
```vba
rowArr(0)  = CreditCode                                       '"TXNDET"
rowArr(1)  = Trim(Me.Cells(r, colCustomerTransacRef).value)  'F  customer txn ref
rowArr(2)  = Trim(Me.Cells(r, colCreditAccNo).value)         'C  credit acc / proxy value
'--- fields 3,4,5 are PRODUCT-BRANCHED (see §7.2) ---
rowArr(3)  = <proxyType>          'PPY: colProxyTypeCode ; else "" (unset for PAY/OAT/3PT/RFT)
rowArr(4)  = <clearing/bank>      'PPY:"111" ; else Trim(Format(colBankCode,"000"))
rowArr(5)  = <branch>             'PPY:"0000" ; PAY-family:"0111" ; RFT:"0000" ; else Trim(colBranchCode)
rowArr(6)  = convertAmountFormat(Me.Cells(r, colAmount).value)
rowArr(7)  = <serviceTypeCode>    'product-branched (see §7.2)
rowArr(8)  = Trim(Me.Cells(r, colFeeChargeCode).value)       'O
rowArr(9)  = checkFlagHaveValue(Me.Cells(r, colSMSNoti).value)   'Y/N
rowArr(10) = removeDashSignPhoneNum(Me.Cells(r, colSMSNoti).value)
rowArr(11) = checkFlagHaveValue(Me.Cells(r, colEmailNoti).value) 'Y/N
rowArr(12) = Trim(Me.Cells(r, colEmailNoti).value)
rowArr(13) = Trim(Me.Cells(r, colRecipientName).value)
rowArr(14) = getRecipientAddress(dataWHT.item(3), CStr(seqNo)) 'WHT sheet col 11 if WHT set, else ""
rowArr(15) = ""                                              'recipient address II
rowArr(16) = ""                                              'recipient address III
rowArr(17) = checkRequiredFlag(dataWHT.item(3))             'WHT required Y/N
rowArr(18) = checkValueWhenFlagIsNoCount(dataWHT.item(3), dataWHT.item(1))  'Total WHT cert count
rowArr(19) = checkValueWhenFlagIsNo(dataWHT.item(3), dataWHT.item(2))       'Total WHT amount
rowArr(20) = checkFlagHaveValue(Me.Cells(r, colEmailNoti).value) 'payment-advice-remark flag (reuses email presence!)
rowArr(21) = checkRequiredFlag(dataInvoice.item(4))         'Invoice required Y/N
rowArr(22) = checkValueWhenFlagIsNoCount(dataInvoice.item(4), dataInvoice.item(1)) 'Total invoice detail
rowArr(23) = checkValueWhenFlagIsNo(dataInvoice.item(4), dataInvoice.item(2))      'Total invoice amount
rowArr(24) = checkValueWhenFlagIsNo(dataInvoice.item(4), dataInvoice.item(3))      'Total VAT amount
rowArr(25) = checkFlagHaveEmailWHT(Me.Cells(r, colEmailNoti).value) 'WHT delivery method: "E" if email else "N"
rowArr(26) = Trim(Me.Cells(r, colEmailNoti).value)          'recipient email for WHT
rowArr(27) = Trim(Me.Cells(r, colPaymentAdviceRemark).value) 'L
res = Join(rowArr, delim)
```

> **Critical re-implementer notes on the TXNDET array:**
> - Field **3 (proxy type)** is only assigned in the `PPY` and the final `Else` branch. For `PAY/PA2/PA3/OAT/3PT` and `RFT`, `rowArr(3)` is **never assigned** → it stays `Empty` and `Join` renders it as an **empty string** (so the field is present-but-blank, not dropped). Same net wire result as `""`.
> - Fields **20**, **25**, **26** all derive from the **email** cell (`colEmailNoti`), not from any dedicated remark/WHT-email cell (the original per-column cells are commented out).
> - Field **14** (`getRecipientAddress`) pulls address from the **WHT** sheet column 11, keyed by seq — only when the WHT required flag (`dataWHT.item(3)`) is 1.

---

### 3. Event handlers

#### 3.1 `Sub Workbook_Open()`
Misnamed workbook-open shim living in the sheet module. Calls `Sheet1.checkProdRadio` to re-apply column layout for whichever product radio is currently selected.
```vba
Sub Workbook_Open()
    Call Sheet1.checkProdRadio
End Sub
```

#### 3.2 `Private Sub Worksheet_SelectionChange(ByVal Target As Range)`
Runs on every selection move. Responsibilities:
1. Repaints `C2` background to `ColorIndex = 15` (grey) each time.
2. If the active product (`M1`) is a payroll/smart family (`PAY,PA2,PA3,SPN,SPS,SPN2,SPS2,SPN3,SPS3`), calls `checkExistingCheckBoxPayroll` (blocks Invoice/WHT for payroll).
3. `If 1 < Target.Cells.count Then Exit Sub` — only single-cell selections proceed.
4. **Cursor-routing / cell "locking"** — a series of `Intersect(...)` guards that set `Cancel = True` and jump the selection to force a data-entry order through the header block:

| Selected range | Action (Offset row,col) |
|---|---|
| `A8:L8` (header row) | down 1 (into data grid) |
| `D2` | right 1 |
| `A2:B2,C2` | down 6 |
| `A3:B3` | right 1 |
| `C2` | down 7 |
| `E5` | down 1 |
| `A5:B6` | right 1 |
| `A4:B4` | right 1 |
| `D3:D4` | right 1 |
| `D5` | down 1 |

> Note the overlapping `C2` rules (down 6 via `A2:B2,C2`, then down 7 via `C2`) — both `Intersect` blocks execute in sequence; the **last** matching `Offset` wins the final selection.

5. **Dropdown-source cascade for data rows** (`If Target.row > idxHeader`): reads `ProductCode = M1`, then switches on `Target.Column`:
   - **`colBank`(2)** → sets `addressBankTable`(N2) + local `tableName` per product (see §7.1 table).
   - **`colFeeCharge`(7)** → sets `addressFeeTable`(O2).
   - **`colServiceType`(9)** → sets `addressServiceTypeTable`(P2).
   - any other column → `Exit Sub`.
   Then rebuilds that cell's in-cell validation list from the chosen Master_data table:
```vba
tableList = getMasterDataList(tableName)
With Target.Validation
    .Delete
    .Add Type:=xlValidateList, AlertStyle:=xlValidAlertStop, _
         Operator:=xlBetween, Formula1:=tableList
    .IgnoreBlank = True : .InCellDropdown = True
    .ShowInput = True : .ShowError = True
End With
```

#### 3.3 `Private Sub Worksheet_Change(ByVal Target As Range)`
Fires on cell edits. Logic:
```vba
If 1 < Target.Cells.count Then Exit Sub   'bulk edits ignored
Me.Unprotect
If Target.row < idxHeader Then
    ValidateCellBankCode Target            'header/debit area (rows <8)
Else
    ValidateCreditSeqNo Target             'credit grid (rows >=8): mainly auto-gen seq no
End If
```
> **Bug/quirk:** the sheet is `Unprotect`-ed but **never re-`Protect`-ed** here (nor in most Validate* routines). After the first edit the sheet stays unprotected. Also, editing exactly on `idxHeader` (row 8) takes the `Else` branch (`< idxHeader` is false).

#### 3.4 `Private Sub Workbook_SheetBeforeDoubleClick(...)`
Globally disables double-click edit-in-cell across sheets: `Cancel = True`. (Another workbook-level event misplaced in the sheet module.)

---

### 4. Header/debit validation entry points

#### 4.1 `Sub ValidateDebit()`
Validates the whole debit/header block on demand:
```vba
Me.Unprotect
res = ValidateCellCustomerBatchRef(range(addressCustomBatchRef)) 'E2
res = ValidateCellDebit(range(addressDebitAcc))                  'C3
res = ValidateCellDebit(range(addressDebitAccFee))               'C4
res = ValidateCellDebit(range(addressValueDate))                 'C5
res = ValidateCellDebit(range(addressDropDownProductType))       'E4
res = ValidateCellDebit(range(addressDebitAccFee))               '(C4 again — redundant)
res = ValidateCellDebit(range(addressProductCode))               'M1
ValidDebitMandatory
```

#### 4.2 `Function ValidateCellBankCode(Target) As Integer`
Called from `Worksheet_Change` for header-area edits. Handles two locations:
- **Column 5 (E), row 4** — the product picklist (`E4`): if a real value (`≠ pleaseSelect`) → resolve `M1` product code from the product table and stamp `addressCustomFileRef`(C2) = `generateCustomerFileReferance & productCode`; else clear `M1`, set `msg="PRODUCT"`.
```vba
Me.range(addressProductCode).value = getCodeConstantsFromMasterData( _
        Me.range(addressProductTable).value, F_getIndexNrListValidation(Target))
```
- **Column 13 (M), row 1** (`M1` written directly, e.g. by a macro) — sets `addressBankTable`(N2) per product family, applies the **column show/hide** rules per product (see §7.3), then re-validates every existing row's `colBank` against the new bank table.

> **Dead tail:** the closing `If msg <> "" Then … Else …` block has **both branches commented out**, so `msg="PRODUCT"` is computed but never surfaces.

#### 4.3 `Function ValidateCellDebit(Target) As Integer`
The main per-cell validator for the header block. Branches on `Target.Column`:
- **Col 3 (C):** row 3 → `ValidateTextFormatSCBAccount("DEBIT_ACC", …,10,10)`; row 4 → `ValidateTextFormatSCBAccount("DEBIT_FEE_ACC",…,10,10)`; row 5 → `ValidateTextFormat("FUTURE_DATE",…,1,10)`.
- **Col 5 (E):** row 2 → `ValidateTextFormat("NOTTHAI",…,1,12)` (customer file ref); row 4 → product-picklist handling (resolve `M1`, set C2 file ref, then `VallidateAll`); else clear `M1`, `msg="PRODUCT"`.
- **Col 13 (M), row 1:** the big product-switch — sets **bank table** (N2), **fee table** (O2) per family, applies **column show/hide** (see §7.3), then loops all data rows re-validating `colBank` (WRONG_BANK), `colFeeCharge` (WRONG_FEE_CHANGE) and `ValidateRowInfo`.
- Trailing: `If msg <> "" Then InvalidCell … Else validCell …` (this one **is** live).

#### 4.4 `Function ValidateCellCustomerBatchRef(Target) As Integer`
Col 5 / row 2 only → `ValidateTextFormatCustomerBatchRef("TEXT_ONLY_ENG", value, 1, 12)`; paints valid/invalid.

#### 4.5 `Sub ValidDebitMandatory()`
Marks required header cells red (`InvalidCell … msgEnter/msgSelect`) when empty: Value Date (C5), Debit Acc (C3), Product dropdown (E4, `msgSelect`), Fee Debit Acc (C4).

---

### 5. Credit-grid validation

#### 5.1 `Function ValidateCreditSeqNo(Target) As Integer`
Called on every credit-grid edit. For columns `colBank, colCreditAccNo, colRecipientName, colAmount, colCustomerTransacRef, colFeeCharge, colBranchCode, colServiceType, colSMSNoti`: if the cell is non-empty, calls `Var = autoGenSeqNo(Target)` — which **auto-assigns the running Seq No in column A** for that row (enforcing "no gaps / not-before-last-record"; see §8). This is how column A fills in as the user types any field in a new row.

#### 5.2 `Function ValidateCell(Target) As Integer` — the master per-column validator
Sets up context (`productTable=M2, bankTable=N2, feeTable=O2, serviceTable=P2, prodCode=M1`), then `Select Case Target.Column`:

| Column | Validation / side-effect |
|---|---|
| `colCreditSeqNo`(1) | `ValidateTextFormat("ACCOUNT_NUMBER",…,1,25)`; if ok and A not numeric → `ValidateTextFormatSCBAccount(…,10,10)`. Writes `colProductTypeCode`(M)=`prodCode`. Defaults `colServiceTypeCode`(P): `01` for PAY/PA2/PA3/SPN…; `04` for SCN/SCS; `00` for BNT. |
| `colBank`(2) | `autoGenSeqNo`; if bank exists in `bankTable` → resolve clearing code via `getCodeConstantsFromMasterDataV2` into `colBankCode`(N); else `msg="WRONG_BANK"`, clear N. |
| `colCreditAccNo`(3) | `ValidateTextFormat("ACCOUNT_NUMBER",…,1,25)`; then **length rules by product** (see §7.4): PAY/PA2/PA3/3PT/OAT→SCB acct 10/10; SPN…/SCN/SCS→ if bank `014` then SCB 10/10; PPY→`ACCOUNT_NUMBER_PPY(10,15)` + per-length proxy-type stamping into `colProxyTypeCode`(T): len 15→`EWL`, 13→`NAT`, 10→`MOB`, else→`TAX`; len 11/12/14 re-validate as national-id ranges. |
| `colRecipientName`(4) | BNT → `ValidateTextFormatBahtNet("TEXT_ONLY_ENG_BAHTNET140",…,1,140)`; else `ValidateTextFormat("NOT_SPECIAL_CHAR",…,1,140)`. |
| `colAmount`(5) | Product-branched (see §7.5): PPY len-15 proxy → `ValidateAmountPromptpay(0.01,10000)` else `ValidateAmountSmart`; SPN…/SCN/SCS → bank `014` → `ValidateAmountCredit(0.01, 9999999999999.99)` else `ValidateAmountSmart`; RFT → `ValidateAmountSmart`; **else → `ValidateAmountCredit`**. |
| `colCustomerTransacRef`(6) | `ValidateTextFormat("TEXT_ONLY_ENG_NUM_SPECIAL",…,1,20)`. |
| `colFeeCharge`(7) | resolve into `colFeeChargeCode`(O) via `getCodeConstantsFromMasterDataV2(feeTable,…)`; else `msg="WRONG_FEE_CHANGE"`. |
| `colBranchCode`(8) | `ValidateTextFormat("FIX_4_NUMBER",…,4,4)`. |
| `colServiceType`(9) | resolve into `colServiceTypeCode`(P) via `getCodeConstantsFromMasterDataV2(serviceTable,…)`; empty → clear P. |
| `colSMSNoti`(10) | `ValidateTextFormatPhoneNum("PHONE_NUMBER",…,10,32)`; set `colNotiSMSFlag`(Q)=Y/N. |
| `colEmailNoti`(11) | `ValidateTextFormat("EMAIL_ADDRESS",…,5,100)`; set `colNotiEmailFlag`(R) **and** `colPaymentAdviceRemarkFlag`(S) = Y/N together. |
| `colPaymentAdviceRemark`(12) | `ValidateTextFormat("NO_SPECIAL_CHAR",…,1,200)`. |

Return contract:
```vba
On Error GoTo errorHandle          'top of function
...
errorHandle:                        'label sits INSIDE the colSMSNoti case (see bug note)
    Select Case Err.Number: Case 13 : 'commented-out handling
...
If msg <> "" Then
    InvalidCell Target.row, Target.Column, msg : ValidateCell = 1
ElseIf Target.Interior.ColorIndex = 3 And IsEmpty(Target.value) Then  'red+empty = mandatory-miss
    ValidateCell = 1
Else
    validCell Target.row, Target.Column
End If
```
> **Bug:** the `errorHandle:` label is physically placed **inside** the `Case colSMSNoti` block (between it and `Case colEmailNoti`). With `On Error GoTo errorHandle` active for the whole function, any runtime error jumps mid-`Select`, and normal fall-through can also reach the label. Its only handler (`Err.Number = 13`, type-mismatch) is commented out, so it's effectively a no-op landing spot.

#### 5.3 `Function ValidateEachCells(row As Integer) As Collection`
Loops columns `1..lastCol` (of header row 8) calling `ValidateCell(Cells(row,i))`; collects the 1-based column indices that returned `>0` (failed) into a `Collection` and returns it.

#### 5.4 `Function ValidateRowInfo(row As Integer)`
Row-level orchestrator:
```vba
If IsEmpty(Cells(row, colCreditSeqNo)) Then
    forceValidRow "Payment", row : Exit Function   'blank seq => treat whole row as valid/blank
End If
Set failColList = ValidateEachCells(row)
IsValid = ValidCreditMandatory(row)
If (failColList.count = 0) And IsValid Then validRow row Else invalidRow row, failColList
```

#### 5.5 `Function ValidCreditMandatory(row) As Boolean`
Per-row mandatory-field gate. Returns `False` if any required field is empty (painting it via `InvalidCell msgEnter/msgSelect`); otherwise re-validates present fields. Required set: `colCreditSeqNo, colBank, colCreditAccNo, colRecipientName, colAmount, colFeeCharge`. Conditional rules:
- **`colServiceType` empty:** for SMART family (`SPS,SPN,SPN2,SPS2,SPN3,SPS3,SCN,SCS`) → forced **valid** (service type optional); else validate.
- **`colBranchCode` empty:** required **unless** product ∈ `{PAY,PA2,PA3,OAT,3PT,PPY,RFT}` — expressed as a long, **redundantly-repeated** boolean chain (PA2/PA3/OAT/3PT appear twice):
```vba
If IsEmpty(Cells(row, colBranchCode)) And (…<>"PAY") And (…<>"PA2" And (…<>"PA3") And (…<>"OAT") And (…<>"3PT")) And (…<>"PPY") And (…<>"PA2" And (…<>"PA3") And (…<>"OAT") And (…<>"3PT")) And (…<>"RFT") Then
```
> The mismatched parentheses make the expression parse in a non-obvious associativity; behaviorally branch code is treated as mandatory only for SCB/other-bank transfer products. A re-implementer should reduce this to: *branch required ⇔ product ∉ {PAY,PA2,PA3,OAT,3PT,PPY,RFT}*.
- **`colServiceTypeCode`(P) empty:** required (`msgSelect`) for `{PAY,PA2,PA3,SPN,SPS,SPN2,SPS2,SPN3,SPS3,BNT}`; else validate.
- The `colCustomerTransacRef` mandatory block is fully commented out (ref is optional).

---

### 6. Export builders (the wire-format core)

#### 6.1 `Function ExportData() As String`
Top-level Payment-sheet body. Concatenates the single `BCHDET` line with all credit lines:
```vba
data.Add ExportDebitRow()
creditInfo = ExportDataCredit()
If creditInfo <> "" Then data.Add creditInfo
ExportData = Join(CollectionToArray(data, 0, data.count), vbNewLine)
```
Invoked by `Export.bas` between the `HEADER|…` line and the `TRAILR|…` line.

#### 6.2 `Function CheckCreditSeqNoBeforExport() As String`
Guard: scans rows `idxHeader+1..lastRow`; if any `colSeqNo`(A) is empty → `MsgBox "Credit seq no is blank. It's not allow to generate text file."` then `End` (**hard-terminates all VBA execution**). Returns nothing meaningful.

#### 6.3 `Function ExportDataCredit() As String`
Builds the credit block, interleaving nested Invoice/WHT records per recipient:
```vba
cbInvoice = Worksheets("Payment").CheckBoxes("InvoiceChk").value
cbWht     = Worksheets("Payment").CheckBoxes("WHTChk").value
lastRow   = Me.Cells(Rows.count, 1).End(xlUp).row
For r = idxHeader + 1 To lastRow
    seqNo = Me.Cells(r, colSeqNo).value
    If IsEmpty(seqNo) Then MsgBox "NOO" : Exit Function     '<-- see bug note
    If Not IsEmpty(seqNo) Then data.Add ExportCreditRow(r)
    If cbInvoice = 1 Then
        invoiceInfo = Worksheets("Invoice").ExportData(Me.Cells(r, colSeqNo).value)
        If invoiceInfo <> "" Then data.Add invoiceInfo
    End If
    If cbWht = 1 Then
        whtInfo = Worksheets("WHT").ExportData(Me.Cells(r, colSeqNo).value)
        If whtInfo <> "" Then data.Add whtInfo
    End If
Next r
If data.count > 0 Then ExportDataCredit = Join(CollectionToArray(data,0,data.count), vbNewLine)
```
> **Bug:** on an empty seq mid-loop it aborts with a bare `MsgBox "NOO"` and returns whatever was accumulated so far (silent truncation) — `CheckCreditSeqNoBeforExport` is meant to prevent reaching here but must be called first by the caller. Nesting order per recipient: **TXNDET → its INVDET(s) → its WHTCER(s)**.

#### 6.4 `Function ExportDebitRow() As String`
Computes `totalCredits`/`totalDebitAmount` via `calculateNumberOfCreditAndAmount(Worksheets("Payment"), colSeqNo, idxHeader+1, colAmount)` then fills the 10-field `BCHDET` (§2.1). Value date passes through `convertDateFormat` (พ.ศ.↔ค.ศ. + `YYYYMMDD`); amount through `convertAmountFormat`.

#### 6.5 `Function ExportCreditRow(r As Integer) As String`
Fills the 28-field `TXNDET` (§2.2). Key setup:
```vba
ProductCode = ThisWorkbook.Sheets("Payment").range("M1").value
seqNo       = Me.Cells(r, colSeqNo).value
BankCode    = Me.Cells(r, colBankCode).value
FormatBankCode = Format(BankCode, "000")           '3-digit zero-padded clearing code
Set dataInvoice = countAndSumInvoice(CStr(seqNo))  'item(1)=count 2=amt 3=vat 4=flag
Set dataWHT     = countAndSumWHT(CStr(seqNo))       'item(1)=count 2=amt 3=flag
```
Product branching for fields 3/4/5 and 7 — full matrix in §7.2.

---

### 7. Product-code driven behavior (the heart of the branching)

Product codes seen: **PPY** (PromptPay), **PAY/PA2/PA3** (payroll), **OAT** (own-account transfer), **3PT** (3rd-party), **RFT** (registered funds transfer / same-day), **SPN/SPS/SPN2/SPS2/SPN3/SPS3** (SMART payroll variants), **SCN/SCS** (SMART credit), **BNT** (BAHTNET). The active code lives in `M1`.

#### 7.1 Dropdown source tables chosen by product (SelectionChange, §3.2 step 5)
| Column edited | Product | Table written to | Cell |
|---|---|---|---|
| Bank (2) | PAY,PA2,PA3,OAT,3PT | `TBBankPAY` | N2 |
| | SPS,SPN,SPN2,SPS2,SPN3,SPS3 | `TBBankWithout014` | N2 |
| | SCN,SCS | `TBBankSmartCredit` | N2 |
| | BNT,RFT | `TBBankBNT1` | N2 |
| | PPY | `TBBankPPY` | N2 |
| | *(else)* | `TBBank` | N2 |
| Fee (7) | BNT | `TBFeeBNT` | O2 |
| | PAY,PA2,PA3,SPN,SPS,SPN2,SPS2,SPN3,SPS3 | `TBFeePayroll` | O2 |
| | *(else)* | `TBFeeOther` | O2 |
| Service (9) | PAY,PA2,PA3 | `TBServiceTypePayroll` | P2 |
| | SPS,SPN,SPN2,SPS2,SPN3,SPS3,SCN,SCS | `TBServiceTypeSmart` | P2 |
| | *(else)* | `TBServiceType` | P2 |

> **Inconsistency:** the bank-table map differs between SelectionChange (§3.2, which distinguishes `SCN,SCS → TBBankSmartCredit`) and the M1-driven paths in `ValidateCellBankCode`/`ValidateCellDebit` (which lump `SCN,SCS` into `TBBankWithout014`). Re-implementers must pick one; the export itself only reads the resolved `colBankCode`, so this only affects the dropdown list offered.

#### 7.2 `TXNDET` fields 3/4/5 and 7 by product (ExportCreditRow)
| Product | f3 proxyType | f4 bank/clearing | f5 branch | f7 serviceTypeCode |
|---|---|---|---|---|
| **PPY** | `colProxyTypeCode`(T) | `"111"` | `"0000"` | `colServiceTypeCode` (via generic Else — but PPY not in the special f7 cases → falls to `Else`) |
| **PAY / PA2 / PA3** | *(unset → "")* | `Trim(Format(colBankCode,"000"))` | `"0111"` | `""` |
| **OAT / 3PT** | *(unset → "")* | `Trim(FormatBankCode)` | `"0111"` | `colServiceTypeCode` (Else) |
| **RFT** | *(unset → "")* | `Trim(FormatBankCode)` | `"0000"` | `colServiceTypeCode` (Else) |
| **SCN / SCS** | `""` (final Else) | `Trim(FormatBankCode)` | `Trim(colBranchCode)` | `checkDefaultValueSmartCredit` → default **`04`** |
| **SPN/SPS/SPN2/SPS2/SPN3/SPS3** | `""` | `Trim(FormatBankCode)` | `Trim(colBranchCode)` | `checkDefaultValueSmartPayroll` → default **`01`** |
| **BNT** | `""` | `Trim(FormatBankCode)` | `Trim(colBranchCode)` | `checkDefaultValueBahtNet` → default **`00`** |
| *(other)* | `""` | `Trim(FormatBankCode)` | `Trim(colBranchCode)` | `colServiceTypeCode` |

The exact f3/f4/f5 branch (`If ProductCode = "PPY" … ElseIf PAY/PA2/PA3/OAT/3PT … ElseIf RFT … Else …`):
```vba
If (ProductCode = "PPY") Then
    rowArr(3) = Trim(Me.Cells(r, colProxyTypeCode).value)
    rowArr(4) = "111" : rowArr(5) = "0000"
ElseIf (ProductCode="PAY") Or ("PA2") Or ("PA3") Or ("OAT") Or ("3PT") Then
    rowArr(4) = Trim(FormatBankCode) : rowArr(5) = "0111"
ElseIf (ProductCode = "RFT") Then
    rowArr(4) = Trim(FormatBankCode) : rowArr(5) = "0000"
Else
    rowArr(3) = "" : rowArr(4) = Trim(FormatBankCode) : rowArr(5) = Trim(Me.Cells(r, colBranchCode).value)
End If
```
The f7 `Select Case ProductCode`:
```vba
Case "SCN", "SCS"                     : rowArr(7) = checkDefaultValueSmartCredit(P)
Case "SPN","SPS","SPN2","SPS2","SPN3","SPS3","SCN","SCS" : rowArr(7) = checkDefaultValueSmartPayroll(P)
Case "BNT"                            : rowArr(7) = checkDefaultValueBahtNet(P)
Case "PAY","PA2","PA3"                : rowArr(7) = ""
Case Else                             : rowArr(7) = P
```
> **Dead-code:** in the f7 switch, `SCN,SCS` are listed in the **second** `Case` too, but the **first** `Case "SCN","SCS"` already catches them → the SmartCredit default (`04`) always wins; the SmartPayroll(`01`) branch never applies to SCN/SCS.

#### 7.3 Column show/hide by product (the `M1`-row-1 branch in `ValidateCellBankCode` / `ValidateCellDebit`)
On `M1` change, columns G/H/I are hidden/shown and some data cleared:
| Product | H (branch) | I (service) | G (fee) | Cleared |
|---|---|---|---|---|
| SPN/SPS/SPN2/SPS2/SPN3/SPS3/SCN/SCS | shown | shown | — | — |
| PAY/PA2/PA3/OAT/3PT | **hidden** | **hidden** | — | H |
| OAT | — | hidden | shown | I, O |
| 3PT | — | hidden | shown | H, O |
| RFT | hidden | hidden | shown | H, P |
| BNT | shown | shown (in ValidateCellDebit: I shown) | shown | P |

> Two near-duplicate copies of this switch exist (`ValidateCellBankCode` lines ~297-370 and `ValidateCellDebit` lines ~437-529) with **subtly different** hide/clear rules (e.g. BNT hides H differently; ValidateCellDebit's version also re-checks fee-table). The `ValidateCellDebit` copy additionally sets the **fee table** (O2) and calls `ValidateRowInfo` per row.

#### 7.4 Credit-account-number length rules (`ValidateCell` colCreditAccNo)
- **PAY/PA2/PA3/3PT/OAT** → must be SCB 10-digit (`ValidateTextFormatSCBAccount(10,10)`).
- **SPN/SPS/SPN2/SPS2/SPN3/SPS3/SCN/SCS** → only if that row's bank code is `014` (SCB) → SCB 10-digit; else no length constraint here.
- **PPY** → `ValidateTextFormatAccount("ACCOUNT_NUMBER_PPY",10,15)`, then by `lenAccount`: 11→(12,13), 12→(13,14), 14→(15,16) national-id revalidation; **15→proxy `EWL`, 13→`NAT`, 10→`MOB`, else→`TAX`** stamped into `colProxyTypeCode`.

#### 7.5 Amount rules (`ValidateCell` colAmount)
- **PPY:** credit-acc length 15 → `ValidateAmountPromptpay(0.01,10000)`; else `ValidateAmountSmart`.
- **SPN/SPS/SPN2/SPS2/SPN3/SPS3/SCN/SCS:** bank `014` → `ValidateAmountCredit(0.01, 9999999999999.99)`; else `ValidateAmountSmart`.
- **RFT:** `ValidateAmountSmart`.
- **all others (Case Else):** `ValidateAmountCredit`.

#### 7.6 Product **radio-button** handlers (set the picklist table M2 + baseline columns)
Each toggles the `E4` product-type dropdown source and default column layout, then `setProductList tableName`.
| Sub | OptionButton | Sets `M2` | Column layout highlights |
|---|---|---|---|
| `Payroll_Click` | "Option Button 10165" | `TBPPPayroll` | hides J,K,L,I; clears J,K,L,I,P; resets E4=`--Select--` |
| `SCBTransfer_Click` | "Option Button 10702" | `TBPPSCBTransfer` | shows H,I,J,K,L; clears H |
| `OtherBankTransfer_Click` | "Option Button 10707" | `TBPPOtherBankTransfer` | shows H,J,K,L (H handling); clears H |
| `PromptPay_Click` | "Option Button 10722" | `TBPPPromptPay` | hides H,I; shows J,K,L; clears I,P,H |

- **`checkProdRadio()`** — reads the four OptionButtons' `.value` and calls the matching `*_Click` (used at Workbook_Open).
- **`setProductList(tbName)`** — rebuilds the `E4` (`addressDropDownProductType`) data-validation list from `getMasterDataList(tbName)`.

---

### 8. Auto-sequence helper (external, but essential to the grid)
`autoGenSeqNo(cell)` (Util.bas) — called from `ValidateCreditSeqNo`/`ValidateCell` on any non-empty grid field. Uses `genSeqNo("A:A")` to find the last used row+seq. Rules when column A of the edited row is empty:
- `cell.row < lastRow` → `MsgBox "Row of record shouldn't be less then last record."` (fail).
- `cell.row = lastRow + 1` → assign `A = lastSeqNo + 1` (the normal path).
- otherwise → `MsgBox "Record shouldn't have space between row."` + clear the edited cell (fail).
This enforces contiguous, monotonically-increasing seq numbers in column A without the user typing them.

---

### 9. Invoice / WHT checkbox handlers

#### 9.1 `Function InvoiceButt_Click() As String`
On the `InvoiceChk` checkbox (`=1` checked):
```vba
If cbValue = 1 Then
    ValidateSheetByName "Invoice"
    Worksheets("Invoice").Visible = True
    Select Case Me.range(addressProductCode).value
      Case "PAY","PA2","PA3","SPN","SPS","SPN2","SPS2","SPN3","SPS3"  'payroll/smart-payroll
          Worksheets("Invoice").Visible = False
          ActiveSheet.CheckBoxes("InvoiceChk").value = Null
          ActiveSheet.CheckBoxes("InvoiceChk").value = False
          MsgBox "The system does not yet support the issuance of Payment Advice and Withholding Tax Certificate for Payroll."
    End Select
Else
    clearValidate "WHT"                 '<-- clears WHT (not Invoice) — likely a copy-paste bug
    Worksheets("Invoice").Visible = False
End If
```
> **Bug:** unchecking Invoice calls `clearValidate "WHT"` instead of `"Invoice"`.

#### 9.2 `Sub WHTChk_Click()`
Symmetric to the above for `WHTChk`; on payroll/smart-payroll products it force-unchecks, hides the WHT sheet, and shows the same "not supported for Payroll" message. Also has the `Else → clearValidate "WHT"` path.
> **Bug:** in the payroll guard it sets `ActiveSheet.CheckBoxes("InvoiceChk").value = Null` (wrong checkbox) before `WHTChk = False`.

#### 9.3 `Sub checkExistingCheckBoxPayroll()`
Called from `SelectionChange` when a payroll/smart-payroll product is active. If either `InvoiceChk` or `WHTChk` is checked → `MsgBox "Payroll is not allow to select invoice and wht sheet."`, clears both validations, hides both sheets, un-checks both boxes. Prevents Invoice/WHT for payroll after the fact.

---

### 10. `Function FindDuplicatesInColumn() As String`
Scans column A (`A1..A65000`) using a `Scripting.Dictionary`; on the first duplicate value → `MsgBox "Please delete a record because it's duplicate."` then `End` (**hard-stops all VBA**).
> **Bug:** the `If Cells(iCntr,1) <> ""` / `If oDictionary.Exists(...)` / `Else` / `End If` nesting is malformed — the inner `If … Exists Then MsgBox: End` has **no matching `Else` at its level** (the `Else`/`oDictionary.Add` binds to the outer `<> ""` test). Consequently the `Add` only runs for **blank** cells, so the dictionary never actually accumulates non-blank keys and real duplicates in A are **not** detected. Effectively dead detection logic.

---

### 11. External helpers whose output defines TXNDET values (from Util.bas / Validation.bas)

| Function | Location | Behavior (as used by ExportCreditRow) |
|---|---|---|
| `calculateNumberOfCreditAndAmount(ws, keyCol, startRow, amtCol)` | Util | Loops from `startRow` while `Cells(iRow,keyCol)` non-empty; returns `Collection{ count, sum(amtCol) }`. Feeds BCHDET f6/f7. |
| `countAndSumInvoice(seq)` | Util | Only if `InvoiceChk=1`. Over Invoice sheet from row 2, matching `Cells(iRow,2)=seq`: `item(1)`=count, `item(2)`=Σ col5 (amount), `item(3)`=Σ col8 (VAT), `item(4)`=required flag(0/1). |
| `countAndSumWHT(seq)` | Util | Only if `WHTChk=1`. Over WHT sheet from row 2, matching col2=seq: `item(1)`=count, `item(2)`=Σ of tax at cols **30,38,46,54,62** (base 30 + 8·k, the 5 income-detail blocks), `item(3)`=required flag. |
| `getRecipientAddress(flag, seq)` | Util | If `flag=0` → `""`. Else scans WHT sheet from row 2; on `col2=seq` returns WHT **col 11** (address). Falls through to `""` if not found. |
| `checkRequiredFlag(f)` | Util | `f=1→"Y"` else `"N"`. |
| `checkValueWhenFlagIsNoCount(f,v)` | Util | `f=0→""` else `CStr(v)`. |
| `checkValueWhenFlagIsNo(f,v)` | Util | `f=0→""` else `convertAmountFormat(CStr(v))`. |
| `checkFlagHaveValue(v)` | Util | non-empty→`"Y"` else `"N"`. |
| `checkFlagHaveEmailWHT(email)` | Util | non-empty→`"E"` else `"N"`. |
| `removeDashSignPhoneNum(v)` | Util | strips `-`. |
| `convertAmountFormat(v)` | Util | `Replace(Replace(FormatNumber(v,2), ",", ""), "", "")` → `"1234.56"` (2 dp, no commas; final `Replace(...,"","")` is a **no-op / dead**). |
| `convertDateFormat(v)` | Util | `convDate` (parses `dd/mm/yyyy`, applies `calYear`), formats `yyyymmdd`, then re-applies `calYear` on the year. **Double `calYear`** is harmless (2nd pass returns the already-CE year unchanged) — see note. |
| `calYear(y)` | Util | `y ≤ Year(Now)+400 → y` (assume CE); else `y-543` (พ.ศ.→ค.ศ.). |
| `checkDefaultValueSmartCredit/Payroll/BahtNet(v)` | Validation | empty→`"04"`/`"01"`/`"00"` else `v`. |
| `getMasterDataList(name)` | Util | returns `"='Master_data'!<addr>"` formula string for the table's first column (validation source). |
| `getCodeConstantsFromMasterData(tbl,idx)` / `…V2(tbl,matchStr)` | Util | resolve display→code from a Master_data ListObject (column 2), by row index / by match. |
| `F_getIndexNrListValidation(cell)` | Validation | returns 1-based index of the cell's current value within its list-validation source (or -1). |
| `checkValueExistInDropDownList(key,tbl)` | Validation | `InListObject` membership test. |
| `VallidateAll` / `ValidateSheetByName(name)` | Validation | loop-validate Payment rows / Invoice·WHT rows. |
| `InvalidCell/validCell/validRow/invalidRow/forceValidRow` | Util | red/yellow/white cell painting + comment + error counter (`N1`). Note `InvalidCell` looks up localized text via `FindErrorMessage(key)` against `TBErrorMessage`. |

---

### 12. Edge cases / bugs / dead code (re-implementer checklist)

1. **`End` statements** in `CheckCreditSeqNoBeforExport` and `FindDuplicatesInColumn` **kill the entire macro** — not just the function. Any orchestrator must call these first, expecting a hard abort on failure.
2. **`FindDuplicatesInColumn` never detects duplicates** (malformed If/Else — §10). Duplicate-seq protection effectively relies on `autoGenSeqNo` contiguity instead.
3. **`ExportDataCredit` silently truncates** on an empty seq (`MsgBox "NOO" : Exit Function`) returning a partial file. Guard with `CheckCreditSeqNoBeforExport`.
4. **Sheet left unprotected:** `Me.Unprotect` is called in nearly every handler; **no `Protect`** is ever re-issued.
5. **`errorHandle:` label mis-placed** inside `ValidateCell`'s `colSMSNoti` case; its only case (`Err 13`) is commented out (§5.2).
6. **`InvoiceButt_Click` / `WHTChk_Click` copy-paste bugs:** wrong checkbox/sheet in the uncheck & payroll-guard branches (§9).
7. **f3 (proxy) left `Empty` for PAY/OAT/3PT/RFT** — renders as empty field via `Join`, not dropped (§2.2).
8. **SCN/SCS unreachable branch** in TXNDET f7 SmartPayroll case (§7.2).
9. **Redundant/mis-parenthesized branch-code mandatory chain** in `ValidCreditMandatory` (§5.5).
10. **Two divergent copies** of the M1 product column-show/hide + bank-table logic (`ValidateCellBankCode` vs `ValidateCellDebit`) with different clear/hide details (§7.3).
11. **Inconsistent bank-table selection** for SCN/SCS between SelectionChange and the validate paths (§7.1).
12. **`convertAmountFormat`** trailing `Replace(...,"","")` is dead; **`convertDateFormat`** applies `calYear` twice (harmless).
13. **`Str(totalDebitAmount)`** in `ExportDebitRow` f6 yields a **leading space** for positive numbers, but `FormatNumber` inside `convertAmountFormat` re-parses it, so the space is dropped — safe, but note the coupling.
14. **Many declared constants are dead** (§1.2, §1.5 `selectProduct`/`colDropDownProduct`, §1.7 all `BCHDET` col consts, §1.2 all `row*`). They document intended layout only; the real writes are positional.
15. **Overlapping cell aliases:** `M1` = both `addressProductCode` and `addressProductCodeForValidate`; `E2` = both `addressCustomBatchRef` and (dead) `selectProduct`; `colSeqNo`≡`colCreditSeqNo`≡column A.
16. **`generateCustomerFileReferance` / `…BatchReferanceName`** both return `Format(Now(),"DDMMYYHHMMSS")` — the customer file ref (`C2`) is built as `<timestamp> & productCode`; the batch ref (`E2`) is user-entered/validated `TEXT_ONLY_ENG` (the auto-gen path is commented out in `Worksheet_Change`).
17. **Record nesting order emitted:** `BCHDET` → for each recipient `TXNDET` then its `INVDET`(s) then its `WHTCER`(s). The surrounding `HEADER` and `TRAILR` lines are added by `Export.bas` (`TRAILR|count|count|amount`), not here.


---

## Sheet4.bas — WHT (Withholding Tax / ภ.ง.ด.) Sheet — Developer Reference

**VBA code name:** `Sheet4` · **Worksheet:** "WHT" (sheet #4) · **~1007 lines · 69 module-level `Const`s.**
Responsible for the **WHTCER** (WHT certificate header) record and the nested **WHTDET** (income-detail) records that are attached under each credit (`TXNDET`) line when the "WHT required" checkbox is set on the Payment sheet.

> **Module-wide caveat:** there is **no `Option Explicit`**. Many working variables (`r`, `tran`, `totalWHT`, `tableList`, `IsValid`, `Cancel`, `i`) are **undeclared implicit Variants**. Several helpers (`convertDateFormat`, `convertAmountFormat`, `delim`, `idxHeader`, `msgEnter`, `msgSelect`, `msgManPercentage`, `addressProductCodeForValidate`, `getMasterDataList`, `getCodeConstantsFromMasterData`, `F_getIndexNrListValidation`, `ValidateTextFormat*`, `ValidateAmount*`, `InvalidCell`, `validCell`, `invalidRow`, `validRow`, `forceValidRow`, `MsgBoxInvalid`, `CollectionToArray`) are **external globals defined in other modules** — a re-implementer must resolve them there.

---

### 1. Record-code constants

| Const | Value | Meaning |
|---|---|---|
| `WHTCode` | `"WHTCER"` | Record code for the WHT-certificate header line; also written into col 1 (`colRecordId`) when a credit seq is entered. |
| `WHTDetail` | `"WHTDET"` | Record code for each income-detail line; written into the `colDetailIdN` cells and emitted as field 0 of every detail block. |
| `idxHeaderWHT` | `1` | Header row index; data rows begin at row 2. |

---

### 2. Column-index constants — **WHT worksheet layout** (all `Integer`)

The WHT sheet is a **flat spreadsheet** where each row = one WHTCER + its up-to-5 income-detail blocks laid out side by side. Note the **spacer columns 23, 31, 39, 47, 55** that separate the header from block 1 and each block from the next; they are unused by export.

#### 2a. WHTCER header columns (cols 1–22)

| Const | Value | Column meaning |
|---|---|---|
| `colRecordId` | 1 | Record Identifier (auto-set to `"WHTCER"`) |
| `colCreditSeqNo` | 2 | Customer Transaction Reference — **join key** linking this WHT row to a Payment/`TXNDET` credit line |
| `colWHTBookNo` | 3 | WHT Book No. |
| `colWHTPayerTaxId` | 4 | WHT Payer Tax ID |
| `colWHTPayerName` | 5 | WHT Payer Name |
| `colWHTPayerAddress1` | 6 | Payer Address Line 1 |
| `colWHTPayerAddress2` | 7 | Payer Address Line 2 |
| `colWHTPayerAddress3` | 8 | Payer Address Line 3 |
| `colWHTRecipientTaxId` | 9 | Recipient Tax ID |
| `colWHTRecipientName` | 10 | Recipient Name |
| `colWHTRecipientAddress1` | 11 | Recipient Address Line 1 |
| `colWHTRecipientAddress2` | 12 | Recipient Address Line 2 |
| `colWHTRecipientAddress3` | 13 | Recipient Address Line 3 |
| `colWHTSeqNo` | 14 | WHT Sequence No |
| `colWHTFormType` | 15 | WHT Form Type — **display/dropdown** value (ภ.ง.ด. form name, from `TBWHTType`) |
| `colWHTFormTypeCode` | 16 | WHT Form Type **Code** — resolved code, this is what is exported |
| `colWHTDeductDate` | 17 | WHT Deduct Date (entered as calendar/พ.ศ. text) |
| `colWHTPayType` | 18 | WHT Pay Type — **display/dropdown** value (from `TBWHTPayType`) |
| `colWHTPayTypeCode` | 19 | WHT Pay Type **Code** — resolved code, exported |
| `colWHTRemarkPayType` | 20 | Remark for Pay Type (mandatory when pay-type code = 4) |
| `colWHTNoWHTDetail` | 21 | No. of WHT Details (auto-computed count) |
| `colWHTDetailAmount` | 22 | Total WHT Detail Amount (auto-computed sum) |

#### 2b. Income-detail block columns (5 blocks × 7 fields, cols 24–62)

Every block N has the same 7-field shape. Value formula per block: `colDetailIdN = 24 + (N-1)*8`, and the 7 fields are at offsets +0..+6.

| Field role | Block 1 | Block 2 | Block 3 | Block 4 | Block 5 |
|---|---|---|---|---|---|
| `colDetailId*` (record id `"WHTDET"`) | 24 | 32 | 40 | 48 | 56 |
| `colDetailIncomeType*` (income type code) | 25 | 33 | 41 | 49 | 57 |
| `colDetailIncomeDes*` (income description) | 26 | 34 | 42 | 50 | 58 |
| `colDetailIncomeRate*` (WHT deduct rate %) | 27 | 35 | 43 | 51 | 59 |
| `colDetailPercentage*` (% dividend to net profit) | 28 | 36 | 44 | 52 | 60 |
| `colDetailIncomeTypeAmount*` (income amount) | 29 | 37 | 45 | 53 | 61 |
| `colDetailAmount*` (WHT amount) | 30 | 38 | 46 | 54 | 62 |

#### 2c. "Credit Page" constants (indices into the **Payment** sheet, not the WHT sheet)

These overlap numerically with WHT-sheet consts (e.g. `colWHTRequired = 25` == `colDetailIncomeType1 = 25`) because they address a **different sheet**.

| Const | Value | Payment-sheet column |
|---|---|---|
| `colCustomerBatchReference` | 2 | Batch reference |
| `colCustomerTransactionReference` | 3 | Credit transaction reference |
| `colWHTRequired` | 25 | "WHT required" flag |
| `colTotalWHTCer` | 27 | Total # of WHT certificates for the credit |
| `colTotalWHTAmount` | 28 | Total WHT amount for the credit |
| `colCreditWHTdeliveryMethod` | 32 | WHT delivery method |
| `colRecipientEmailFotWHT` | 33 | Recipient email for WHT (typo "Fot") |
| `colProductCode` | 4 | Product code |
| `sheetname` | `"WHT"` (untyped) | Sheet name string passed to validation helpers |

Also declared: `Dim ProductCode As String` (module-level), set from the Payment sheet inside validators.

---

### 3. Export path — the record layout a re-implementer must reproduce

#### `Function ExportData(ref As String) As String`
**Params:** `ref` = the credit transaction reference (the `colCreditSeqNo` key).
**Purpose:** collect every WHT row whose `colCreditSeqNo == ref`, emit its WHTCER header line plus its WHTDET detail line(s), newline-joined.

Key logic:
```vba
lastRow = Me.Cells(Rows.count, 2).End(xlUp).row      ' last used row in col 2 (colCreditSeqNo)
For r = 2 To lastRow
    If Me.Cells(r, colCreditSeqNo).value = ref Then
        data.Add ExportWHTRow(r)                     ' one WHTCER line
        WHTDetail = ExportWHTDetailRow(r)            ' 1..5 WHTDET lines (newline-joined)
        If WHTDetail <> "" Then data.Add WHTDetail
    End If
Next r
If data.count > 0 Then
    resData = Join(CollectionToArray(data, 0, data.count), vbNewLine)
    ExportData = resData
End If
```
**Side-effects:** none (read-only). **Returns** the multi-line block, or `""` when no matching row.

> **Critical structural fact (differs from the "nested fields" summary):** the WHTCER header and each income-detail block are emitted as **separate physical lines** joined by `vbNewLine`, *not* concatenated onto one WHTCER line. The on-disk shape for one certificate is:
> ```
> WHTCER|…19 fields…
> WHTDET|…7 fields…   (block 1)
> WHTDET|…7 fields…   (block 2, if present)
> …up to block 5…
> ```
> Multiple WHTCER blocks can appear for one `ref` if multiple WHT rows share the same credit seq (loop adds each).
>
> **Edge case:** `ExportWHTDetailRow` **always** emits block 1 (no emptiness guard), so `WHTDetail` is never `""` for a matched row — the `If WHTDetail <> ""` guard is effectively always true. If block-1 detail cells are blank, a `WHTDET||||||` line is still produced (field 0 = `Trim(colDetailId1)` which would be empty rather than `"WHTDET"`).

#### `Function ExportWHTRow(r As Integer) As String` — the **19-field WHTCER header**
`ReDim rowArr(18)` → indices 0–18 (19 fields), `Join(rowArr, delim)` with `delim` = `"|"`.

Exact field-order array (quote verbatim):
```vba
rowArr(0) = "WHTCER"                                              ' record code (hardcoded)
rowArr(1) = Trim(Me.Cells(r, colWHTBookNo).value)                ' col 3
rowArr(2) = Trim(Me.Cells(r, colWHTPayerTaxId).value)            ' col 4
rowArr(3) = Trim(Me.Cells(r, colWHTPayerName).value)             ' col 5
rowArr(4) = Trim(Me.Cells(r, colWHTPayerAddress1).value)         ' col 6
rowArr(5) = Trim(Me.Cells(r, colWHTPayerAddress2).value)         ' col 7
rowArr(6) = Trim(Me.Cells(r, colWHTPayerAddress3).value)         ' col 8
rowArr(7) = Trim(Me.Cells(r, colWHTRecipientTaxId).value)        ' col 9
rowArr(8) = Trim(Me.Cells(r, colWHTRecipientName).value)         ' col 10
rowArr(9) = Trim(Me.Cells(r, colWHTRecipientAddress1).value)     ' col 11
rowArr(10) = Trim(Me.Cells(r, colWHTRecipientAddress2).value)    ' col 12
rowArr(11) = Trim(Me.Cells(r, colWHTRecipientAddress3).value)    ' col 13
rowArr(12) = Trim(Me.Cells(r, colWHTSeqNo).value)                ' col 14
rowArr(13) = Trim(Me.Cells(r, colWHTFormTypeCode).value)         ' col 16  (CODE, not display col 15)
rowArr(14) = Trim(convertDateFormat(Me.Cells(r, colWHTDeductDate).value))  ' col 17 -> YYYYMMDD
rowArr(15) = Trim(Me.Cells(r, colWHTPayTypeCode).value)          ' col 19  (CODE, not display col 18)
rowArr(16) = Trim(Me.Cells(r, colWHTRemarkPayType).value)        ' col 20
rowArr(17) = Trim(Me.Cells(r, colWHTNoWHTDetail).value)          ' col 21  No. of WHT Details
rowArr(18) = convertAmountFormat(Me.Cells(r, colWHTDetailAmount).value)    ' col 22  Total WHT Detail Amount
res = Join(rowArr, delim)
```

WHTCER field map (0-indexed → pipe position):

| Idx | Field | Source col | Transform |
|---|---|---|---|
| 0 | Record code | — | literal `"WHTCER"` |
| 1 | WHT Book No | 3 | Trim |
| 2 | Payer Tax ID | 4 | Trim |
| 3 | Payer Name | 5 | Trim |
| 4–6 | Payer Address 1–3 | 6–8 | Trim |
| 7 | Recipient Tax ID | 9 | Trim |
| 8 | Recipient Name | 10 | Trim |
| 9–11 | Recipient Address 1–3 | 11–13 | Trim |
| 12 | WHT Seq No | 14 | Trim |
| 13 | **Form-type CODE** | **16** | Trim (resolved from display col 15) |
| 14 | Deduct Date | 17 | `convertDateFormat` → `YYYYMMDD` |
| 15 | **Pay-type CODE** | **19** | Trim (resolved from display col 18) |
| 16 | Remark for pay type | 20 | Trim |
| 17 | No. of WHT details | 21 | Trim (auto-count) |
| 18 | Total WHT detail amount | 22 | `convertAmountFormat` |

> Note: `colCreditSeqNo` (col 2) is the join key but is **deliberately not exported** — the original `rowArr(1) = Trim(...colCreditSeqNo...)` line is commented out and replaced by `colWHTBookNo`. The exported form-type and pay-type come from the **code** columns (16, 19), which are auto-filled by validation from `TBWHTType` / `TBWHTPayType` — see §5.

#### `Function ExportWHTDetailRow(r As Integer) As String` — **up to 5 WHTDET blocks × 7 fields**
`ReDim rowArr(6)` → indices 0–6 (7 fields per block). Block 1 is built and assigned to `finalRes` unconditionally; blocks 2–5 are each appended with a leading `vbNewLine` **only if `Not IsEmpty(colDetailIdN)`**.

Block-1 array (verbatim; blocks 2–5 are identical with the `N` suffix bumped):
```vba
rowArr(0) = Trim(Me.Cells(r, colDetailId1).value)                         ' "WHTDET"
rowArr(1) = Trim(Me.Cells(r, colDetailIncomeType1).value)                 ' income type code
rowArr(2) = Trim(Me.Cells(r, colDetailIncomeDes1).value)                  ' income description
rowArr(3) = convertAmountFormat(Me.Cells(r, colDetailIncomeRate1).value)  ' WHT rate %
If IsEmpty(Me.Cells(r, colDetailPercentage1).value) Then
    rowArr(4) = Trim(Me.Cells(r, colDetailPercentage1).value)             ' -> "" when not applicable
Else
    rowArr(4) = convertAmountFormat(Me.Cells(r, colDetailPercentage1).value)  ' % dividend to net profit
End If
rowArr(5) = convertAmountFormat(Me.Cells(r, colDetailIncomeTypeAmount1).value) ' income amount
rowArr(6) = convertAmountFormat(Me.Cells(r, colDetailAmount1).value)          ' WHT amount
res = Join(rowArr, delim)
finalRes = finalRes & res
```
Blocks 2–5 conditional append:
```vba
If Not IsEmpty(Me.Cells(r, colDetailId2).value) Then
    ReDim rowArr(6)
    … same 7 assignments with the "2" suffix …
    res = Join(rowArr, delim)
    finalRes = finalRes & vbNewLine & res
End If
' identical guarded blocks for colDetailId3, colDetailId4, colDetailId5
```

WHTDET field map (per block):

| Idx | Field | Block-N source col | Transform |
|---|---|---|---|
| 0 | Detail record id | `colDetailIdN` | Trim (value `"WHTDET"`) |
| 1 | Income Type (code) | `colDetailIncomeTypeN` | Trim |
| 2 | Income Description | `colDetailIncomeDesN` | Trim |
| 3 | WHT Deduct Rate % | `colDetailIncomeRateN` | `convertAmountFormat` |
| 4 | % Dividend to Net Profit | `colDetailPercentageN` | `convertAmountFormat`, **or `""` (Trim) when empty** |
| 5 | Income Type Amount | `colDetailIncomeTypeAmountN` | `convertAmountFormat` |
| 6 | WHT Amount | `colDetailAmountN` | `convertAmountFormat` |

**Block-append rule:** block 1 always present; block N (2–5) present ⟺ `colDetailIdN` non-empty (set by validation to `"WHTDET"` when its income type is filled). `colWHTNoWHTDetail` (WHTCER field 17) should equal the number of blocks emitted; it is computed independently in `UpdateWHTNoAndTotalAmountDetail` (§4) by counting non-empty `colDetailIdN`.

---

### 4. Helper subs that maintain header roll-ups

#### `Sub UpdateWHTNoAndTotalAmountDetail(row As Integer)`
Recomputes, for **every row sharing this row's `colCreditSeqNo`**, the detail count and total, then **locks** the two summary cells.
```vba
tran = Cells(row, colCreditSeqNo).value
r = 1
Do Until IsEmpty(Me.Cells(r, colCreditSeqNo).value)
    If tran = Me.Cells(r, colCreditSeqNo).value Then
        totalWHT = IIf(Not IsEmpty(Me.Cells(r, colDetailId1).value),1,0) + … + IIf(Not IsEmpty(Me.Cells(r, colDetailId5).value),1,0)
        totalWHTAmount = Me.Cells(r, colDetailAmount1).value + … + Me.Cells(r, colDetailAmount5).value
        totalWHTCert = totalWHTCert + 1
        Me.Cells(r, colWHTNoWHTDetail).value = totalWHT
        Me.Cells(r, colWHTDetailAmount).value = totalWHTAmount
        Me.Cells(r, colWHTNoWHTDetail).Locked = True
        Me.Cells(r, colWHTDetailAmount).Locked = True
    End If
    r = r + 1
Loop
```
**Side-effects:** writes cols 21 & 22 and sets `.Locked = True`. **Bug/edge:** `totalWHTAmount` sums all five `colDetailAmount*` cells directly — if any is empty/blank this can error or coerce; `totalWHTCert` is incremented but never used (the roll-up to the credit line is done elsewhere). Called from `ValidateRowInfo` after a row validates OK.

#### `Sub UpdateCreditWithWHT(key As String, totalWHTCert As Integer, totalWHTAmount As Double)`
Walks rows by `colCreditSeqNo == key`, writes `totalWHTCert`→`colTotalWHTCer(27)` and `totalWHTAmount`→`colTotalWHTAmount(28)`, then `Exit Sub` on first match.
> **Suspect:** it writes the **Payment-page** column indices (27/28) into **`Me`** (the WHT sheet). Not called anywhere in this module — likely **dead or externally invoked**; a re-implementer should not trust it to update the Payment sheet.

#### `Function findDuplicateByKey(tbName, col, key) As Integer`
Intended to find a row in a ListObject where column `col` == `key`. **Broken/dead:** the loop counter `r` is never initialized (`Do Until IsEmpty(tbl.DataBodyRange(r, col).value)` with `r=0` → out-of-range on a 1-based `DataBodyRange`). Not called in this module.

---

### 5. Master_data interplay (dropdowns → code resolution)

Three Master_data ListObjects drive the WHT dropdowns and code look-ups:

| Master_data table | Feeds column(s) | Purpose |
|---|---|---|
| `TBWHTType` | `colWHTFormType` (15) → code into `colWHTFormTypeCode` (16) | ภ.ง.ด. **form type** (e.g. ภ.ง.ด.1ก/2/3/53) |
| `TBWHTPayType` | `colWHTPayType` (18) → code into `colWHTPayTypeCode` (19) | **payment condition** type (withhold / pay-once / pay-always / other) |
| `TBIncomeType` | `colDetailIncomeType1..5` (25/33/41/49/57) | income category codes (see magic codes below) |

**Dropdown population** — `Worksheet_SelectionChange` rebuilds cell validation on entry:
```vba
Case colWHTFormType:      tableName = "TBWHTType"    '"ListWHTFormType"
Case colWHTPayType:       tableName = "TBWHTPayType" '"ListPayType"
Case colDetailIncomeType1, …Type5: tableName = "TBIncomeType"
…
tableList = getMasterDataList(tableName)
With Target.Validation: .Delete: .Add Type:=xlValidateList, …, Formula1:=tableList: … End With
```
Also, for `colCreditSeqNo`, it builds a dropdown of valid credit references sourced from the Payment sheet:
```vba
.Add …, Formula1:="=Payment!A" & idxHeader + 1 & ":A" & lastRow
```

**Code resolution** — in `ValidateCell`, when the display cell changes, the paired *code* cell is filled by index look-up:
```vba
Case colWHTFormType:
    Me.Cells(Target.row, colWHTFormTypeCode).value = getCodeConstantsFromMasterData("TBWHTType",   F_getIndexNrListValidation(Target))
Case colWHTPayType:
    Me.Cells(Target.row, colWHTPayTypeCode).value = getCodeConstantsFromMasterData("TBWHTPayType", F_getIndexNrListValidation(Target))
```
`F_getIndexNrListValidation(Target)` returns the 1-based position of the chosen item in the dropdown list; `getCodeConstantsFromMasterData` maps that position to the numeric code stored in the Master_data table. Clearing the display cell clears the code cell. **The export uses only the code columns (16/19).**

#### Income-type magic codes (hard-coded business rules)

| Code | Behavior in this module |
|---|---|
| `"6"` | "Other" income — **may be duplicated up to 3×** per transaction (`DuplicateDetailIncomeType`); also requires an income **description** (`ValidWHTMandatory`). It is the code `ValidateDetailIncomeType` looks for to permit a 4th/5th detail block. |
| `"4b2.5"` | Requires an income **description** to be present. |
| `"4b1.4"` | Requires the **% dividend to net profit** field (`colDetailPercentageN`) — dividend income. |
| `"4"` | Referenced implicitly via the `4b*` families. |

---

### 6. Detail-count / duplicate guards

#### `Sub ValidateDetailIncomeType(row As Integer, col As Integer)`
Guards adding a 4th/5th detail: if **none** of income types 1/2/3 equals `6`, clears the just-entered cell and warns.
```vba
Me.Unprotect
If (Cells(row, colDetailIncomeType1).value <> 6) And (…Type2 <> 6) And (…Type3 <> 6) Then
    Me.Cells(row, col).value = ""
    MsgBox "Maximum of WHT detail are 3"
End If
```
> Business intent: only income type 6 may repeat, so a 4th/5th block is only legitimate when a `"6"` already exists among the first three. **Note the `<> 6` numeric compare vs. the string `"6"` used elsewhere** — a coercion inconsistency to preserve or fix deliberately.

#### `Sub DuplicateDetailIncomeType(row As Integer, incomeType As String)`
Counts how many of the five income-type cells equal `incomeType`. If not `"6"` and count > 1 → warn *"Allow only 3 different types of income per transaction."*; if `"6"` and count > 3 → warn *"Allow duplicated maximum 3 times per transaction for type of income No. 6"*. Empty `incomeType` → `Exit Sub`. **Warn-only (no auto-clear).**

---

### 7. Event handlers

#### `Private Sub Worksheet_SelectionChange(ByVal Target As range)`
- Guard: `If 1 > Target.Cells.count Then Exit Sub` (empty selection).
- If selection hits header `B1:BJ1`: sets `Cancel = True` (**dead — `Cancel` is not a parameter of `SelectionChange`, so this is a no-op implicit Variant**) and moves one row down.
- If `Target.Column = colCreditSeqNo` and below header: builds a credit-reference dropdown from `Payment!A(idxHeader+1):A(lastRow)`.
- Below header, `Select Case Target.Column`: builds `xlValidateList` validation from `TBWHTType` / `TBWHTPayType` / `TBIncomeType` (per §5); `Case Else Exit Sub`.
- A commented-out block (lines 118–121) that would have auto-advanced the cursor across the header is disabled; trailing commented `clearValidate`/`VallidateAll` "retry" lines are dead.

#### `Private Sub Worksheet_Change(ByVal Target As range)`
Only reacts to `colCreditSeqNo` below the header: if the cell is emptied, clears `colRecordId`; otherwise stamps `colRecordId = WHTCode` (`"WHTCER"`). The `ValidateCell Target` call is commented out.

---

### 8. `Function ValidateCell(ByVal Target As range) As Integer`

The per-cell validation dispatcher. `Me.Unprotect` at entry; `On Error GoTo errorHandle`; reads `ProductCode` from `Payment!<addressProductCodeForValidate>`. Big `Select Case Target.Column`. Returns `1` if invalid, else marks the cell valid and returns `0`.

Validation rules by column (format strings are passed to external validators):

| Column | Validator call | Rule |
|---|---|---|
| `colCreditSeqNo` (2) | `ValidateTextFormat("NUMBER", v, 1, 10)` (only if non-empty) | numeric, 1–10 chars |
| `colWHTRecipientTaxId` (9) | `ValidateTextFormatRecipientTax("NO_SPECIAL_CHAR", v, 1, 15)` | 1–15, no special chars |
| `colWHTRecipientName` (10) | non-empty → `ValidateTextFormatBahtNet("NOT_SPECIAL_CHAR", v,1,140)`; empty → `ValidateTextFormatRecipientName(v,1,140)` | max 140 (**inverted** empty/non-empty branch — see note) |
| `colWHTRecipientAddress1/2/3` (11/12/13) | `ValidateTextFormatRecipientAdds("SPECIAL_CHAR", v, 1, 70)` (if non-empty) | 1–70, special chars **allowed** |
| `colWHTFormType` (15) | resolves `colWHTFormTypeCode`, or clears it if empty | — |
| `colWHTDeductDate` (17) | `ValidateTextFormat("DATE", v, 1, 10)` | date, ≤10 chars |
| `colWHTPayType` (18) | resolves `colWHTPayTypeCode`, or clears it | — |
| `colWHTRemarkPayType` (20) | `ValidateTextFormat("NO_SPECIAL_CHAR", v, 1, 40)` | 1–40, no special chars |
| `colDetailIncomeType1` (25) | `DuplicateDetailIncomeType`; sets `colDetailId1 = "WHTDET"`, or clears it | detail-1 needs no predecessor |
| `colDetailIncomeDes1` (26) | `ValidateTextFormatIncomeDesc("NO_SPECIAL_CHAR", v, 1, 80)` | 1–80 |
| `colDetailIncomeRate1` (27) | `ValidateAmountWHTPercentage("AMOUNT", v, , 100)` | 0–100 |
| `colDetailPercentage1` (28) | `ValidateAmountWHTPercentage("AMOUNT", v, 0.01, 100)` | 0.01–100 |
| `colDetailIncomeTypeAmount1` (29) | `ValidateAmount("AMOUNT", v)` | amount |
| `colDetailAmount1` (30) | `ValidateAmountInvoiceAmount("AMOUNT", v, -9999999999999.99, 9999999999999.99)` | **allows negative** |
| Income Type 2–5 (33/41/49/57) | clear own `colDetailIdN`; require the previous income types to be filled (`MsgBoxInvalid`), else `DuplicateDetailIncomeType` + set `colDetailIdN = "WHTDET"`; types 4 & 5 also call `ValidateDetailIncomeType` | ordered entry enforced |
| Income Des 2–5 | `ValidateTextFormatIncomeDesc("NO_SPECIAL_CHAR", v, 1, 80)` | 1–80 |
| Rate 2–5 | `ValidateAmountWHTPercentage("AMOUNT", v, , 100)` | ≤100 |
| Percentage 2–5 | `ValidateAmountWHTPercentage("AMOUNT", v, 0.01, 100)` | 0.01–100 |
| IncomeTypeAmount 2–5 | `ValidateAmount("AMOUNT", v)` | amount |
| DetailAmount 2–5 | `ValidateAmountInvoiceAmount("AMOUNT", v, 0.01, 9999999999999.99)` | **min 0.01 (no negatives)** |

Ordered-entry gating example (income type 5):
```vba
Case colDetailIncomeType5
    Me.Cells(Target.row, colDetailId5).ClearContents
    If Not IsEmpty(Target.value) Then
        If IsEmpty(…Type1) Or IsEmpty(…Type2) Or IsEmpty(…Type3) Or IsEmpty(…Type4) Then
            MsgBoxInvalid "Enter WHT Income Type 1, 2, 3, and 4 first"
            Me.Cells(Target.row, colDetailIncomeType5).value = ""
            Me.Cells(Target.row, colDetailId5).ClearContents
        Else
            ValidateDetailIncomeType Target.row, colDetailIncomeType5
            DuplicateDetailIncomeType Target.row, Target.value
            Me.Cells(Target.row, colDetailId5).value = WHTDetail
        End If
    End If
```

Error tail + verdict:
```vba
errorHandle:
    Select Case Err.Number
    Case 13
        MsgBox "Successfully pasted all text."     ' type-mismatch treated as a paste success
    End Select
If msg <> "" Then
    InvalidCell Target.row, Target.Column, msg, sheetname
    ValidateCell = 1
ElseIf Target.Interior.ColorIndex = 3 And IsEmpty(Target) Then   ' red = mandatory still blank
    ValidateCell = 1
Else
    validCell Target.row, Target.Column, sheetname
End If
```
> **Re-implementer notes / quirks:**
> - The `errorHandle:` label is **not preceded by `Exit Function`**, so on the normal (no-error) path execution *falls through* into it with `Err.Number = 0` (harmless, Case 13 skipped).
> - **Detail-1 WHT amount allows negatives** (`-9,999,999,999,999.99`) while details 2–5 are floored at `0.01` — an intentional-looking asymmetry that a re-implementer should confirm.
> - The `colWHTRecipientName` branch is logically inverted (special-char check when a value exists; min/max — which fails on min — only when empty). The `BNT`/BahtNet product-code branches for recipient name & addresses are all **commented out**; the live code always uses the non-BNT path.

### 9. Row-level validation orchestration

#### `Function ValidateEachCells(row As Integer) As Collection`
Finds last used header column (`Cells(idxHeaderWHT, Columns.count).End(xlToLeft).Column`), calls `ValidateCell` on every cell `1..lastCol` of `row`, collects the 1-based column indices that failed (`res > 0`).

#### `Sub ValidateRowInfo(row As Integer)`
Row entry point:
```vba
If IsEmpty(Cells(row, colCreditSeqNo)) Then forceValidRow sheetname, row : Exit Sub
IsValid = ValidWHTMandatory(row)
Set failColList = ValidateEachCells(row)
If (failColList.count = 0) And IsValid Then
    validRow row, sheetname
    UpdateWHTNoAndTotalAmountDetail (row)     ' recompute + lock cols 21/22
Else
    invalidRow row, failColList, sheetname
End If
```
An empty credit-seq row is treated as a valid (unused) row.

#### `Function ValidWHTMandatory(row As Integer) As Boolean`
Returns `False` if any required field is missing (marks each via `InvalidCell`). Requirements:
- **Always:** `colCreditSeqNo`, `colWHTRecipientTaxId`, `colWHTRecipientName`, `colWHTRecipientAddress1`, `colWHTFormType`, `colWHTDeductDate`, `colWHTPayType`, plus **`colWHTRemarkPayType` when `colWHTPayTypeCode = 4`**.
- **Detail 1 (always):** `colDetailIncomeType1`, `colDetailIncomeRate1`, `colDetailIncomeTypeAmount1`, `colDetailAmount1`; `colDetailIncomeDes1` required **iff** income type1 ∈ {`"4b2.5"`, `"6"`}; `colDetailPercentage1` required **iff** income type1 = `"4b1.4"`.
- **Details 2–5:** the same set (Des-if-4b2.5/6, Rate, Percentage-if-4b1.4, IncomeTypeAmount, DetailAmount) is enforced **only when that block's income type is non-empty**.

`ProductCode` is read from `Payment!M1` (twice — redundant). The message for a missing credit-seq: *"Please select the information this field. The system support maximum 1 WHT per credit line."* The commented `ValidateTextFormatRecipientAddsBNT`/BahtNet paths and `percentageNetProfit` lookup are dead. The trailing `UpdateWHTNoAndTotalAmountDetail (row)` is commented out (roll-up happens in `ValidateRowInfo` instead).

---

### 10. Bugs / dead code / re-implementation gotchas (consolidated)

1. **WHTDET emitted as separate lines**, not concatenated onto the WHTCER line (see §3). This is the single most important structural fact.
2. **Block 1 is always emitted** by `ExportWHTDetailRow` with no emptiness guard; the `If WHTDetail <> ""` in `ExportData` is effectively always true.
3. **Export uses code columns 16/19**, not the display columns 15/18; and **omits `colCreditSeqNo`** (join key) from the WHTCER line.
4. `colCreditSeqNo` is used for de-dup/matching but the exported header starts at Book No — a re-implementer must key on col 2 while never emitting it.
5. **Detail-1 WHT amount permits negatives** (range `-9,999,999,999,999.99 … 9,999,999,999,999.99`); details 2–5 are floored at `0.01`.
6. `colWHTRecipientName` validation branch is **inverted** (empty→min/max, non-empty→special-char).
7. `Cancel = True` inside `Worksheet_SelectionChange` is a **no-op** (no such parameter); creates an implicit Variant.
8. `findDuplicateByKey` is **broken** (uninitialized 1-based index `r=0`) and unused.
9. `UpdateCreditWithWHT` writes **Payment-page column indices into the WHT sheet (`Me`)** and is **not called** here — treat as dead/external.
10. `ValidateDetailIncomeType` compares income type `<> 6` **numerically** while the rest of the module compares against the **string** `"6"` — coercion inconsistency.
11. Error handler treats **type-mismatch (Err 13) as "Successfully pasted all text."** — surprising UX on paste of mixed types.
12. **No `Option Explicit`**; many implicit Variants (`r`, `tran`, `totalWHT`, `tableList`, `IsValid`, `i`).
13. Multiple commented-out branches for **product code `"BNT"`/BahtNet** in recipient name/address validation — the BahtNet-specific rules are inert; the workbook currently validates all products identically here.
14. **Amount/date transforms are external:** `convertAmountFormat` → `FormatNumber(x,2)` with commas stripped → `"1234.56"`; `convertDateFormat` → `YYYYMMDD` with พ.ศ.↔ค.ศ. year conversion; `delim` = `"|"`. These live in a shared module, not Sheet4.
15. Spacer columns **23, 31, 39, 47, 55** exist between header and blocks; unused by export (export reads named consts directly).
16. `colWHTNoWHTDetail`/`colWHTDetailAmount` (cols 21/22) are **auto-computed and `.Locked = True`** after a successful row validation — not user-entered.


---

## Reference: `Util.bas`, `ThisWorkbook.bas`, and the empty modules (`Sheet5`/`Sheet6`/`Sheet8`/`UserForm1`)

> Source files: `/private/tmp/claude-501/-Users-nest-Documents-pguard/c7cb34b5-0bee-46b1-afc9-39a9331d53a3/scratchpad/vba/{Util,ThisWorkbook,Sheet5,Sheet6,Sheet8,UserForm1}.bas`

---

### 1. `Util.bas` — shared helper library (~625 lines)

#### 1.0 Module-wide facts a re-implementer MUST know

- **No `Option Explicit`.** Every bare identifier that is never `Dim`-ed is an implicit `Variant`. This library relies on that heavily (loop counters `r`, `iRow`, `row`; accumulators `countNumberOfCreditByCusRef`, `sumAmountByCusRef`, `numberOfInvoiceDetail`, …; and the cross-procedure implicit `errMsg`, `CountError`). None of these are declared.
- **External symbol `idxHeader`** is used but **not defined here**. It is a global constant/var defined elsewhere (in `Sheet1`, the Payment sheet code-behind) = the Payment sheet's header row index (the row directly above the first data row). Referenced by `forceValidRow`, `invalidRow`, `genSeqNo`, and by `ThisWorkbook`.
- **External symbol `Sheet1`** (the Payment sheet's code name) — `ThisWorkbook` calls `Sheet1.checkProdRadio`, not in this file.
- All Thai comments/messages are decoded here as TIS-620/cp874. This module contains no Thai string literals in live code (only English debug/`MsgBox` text).
- Many procedures use **unqualified `Cells`/`Rows`/`ActiveSheet`/`range(...)`** → they silently operate on whatever sheet is currently active, which is a correctness hazard when called from the wrong context.
- `getActiveSheet` resolves against **`ThisWorkbook`** (not `ActiveWorkbook`), defaulting to the `"Payment"` sheet.

#### 1.1 Module-level `Public Const` (cell-address map for the Payment sheet header block)

| Const | Value | Meaning (Payment sheet cell) |
|---|---|---|
| `addressCountError` | `"N1"` | running error-count cell |
| `addressCustomFileRef` | `"C2"` | customer file reference (HEADER field 2) |
| `addressDebitAcc` | `"C3"` | debit account (BCHDET) |
| `addressDebitAccFee` | `"C4"` | debit fee account (BCHDET) |
| `addressValueDate` | `"C5"` | value date (BCHDET, YYYYMMDD) |
| `addressCustomBatchRef` | `"E2"` | batch reference (BCHDET) |
| `addressDropDownProductType` | `"E4"` | product-type dropdown (→ productCode) |
| `addressSystemReferenceId` | `"E6"` | system reference id (HEADER field 3) |

Two additional **local** consts exist inside functions: `Const firstRow = 2` (in `findDuplicateRow`) and `Const firstRow = 10` (in `genSeqNo`, **unused/dead** — never referenced in the body).

---

#### 1.2 Format / conversion functions (the file-format core)

##### `convertAmountFormat(value As String) As String`
Formats a money value into the pipe-file's `1234.56` form.
```vba
formatNum = FormatNumber(value, 2)          ' locale: "1,234.56"
removeCommar = Replace(formatNum, ",", "")  ' "1234.56"
convertAmountFormat = Replace(removeCommar, "", "")   ' NO-OP (empty Find → returns unchanged)
```
- **Logic:** `FormatNumber(x,2)` → 2 decimals with locale thousands separators, then strip commas. The final `Replace(…, "", "")` is a **leftover dead line** (VBA `Replace` with an empty Find-string returns the string unchanged; the period-stripping it once did is commented out on the line above).
- **Exact I/O:**

  | input | `FormatNumber(x,2)` | output |
  |---|---|---|
  | `"1234.5"` | `"1,234.50"` | `1234.50` |
  | `"1000000"` | `"1,000,000.00"` | `1000000.00` |
  | `"0"` | `"0.00"` | `0.00` |
  | `"0.005"` | `"0.01"`* | `0.01` |

  \*Rounding is VBA `FormatNumber` rounding (banker's/round-half-to-even in most builds) — re-implementers must match the bank spec's rounding, not assume half-up.
- **Edge/bug:** locale-dependent. On a locale whose thousands separator is not `,` (e.g. some European locales use `.`), `FormatNumber` emits `1.234,56` and the comma-strip leaves a corrupt value. Negative inputs may render as `(1,234.56)` (parentheses per regional "use-parens-for-negatives"), which survives the comma-strip → malformed. Amounts are expected non-negative so this normally doesn't fire.

##### `convertDateFormat(value As String) As String`  → **contains a latent leading-space bug**
Converts a `dd/mm/yyyy` (Buddhist or Gregorian year) into the file's `YYYYMMDD`.
```vba
dateString = Format(convDate(value), "yyyymmdd")   ' already Gregorian, e.g. "20241225"
yearString = Mid(dateString, 1, 4)                 ' "2024"
calDCyear  = calYear(Int(yearString))              ' calYear(2024) = 2024 (no-op)
convertDateFormat = Replace(dateString, yearString, str(calDCyear))
```
- **Critical bug:** `convDate` already converted the year to Gregorian, so the second `calYear` is a no-op, and the final line replaces `"2024"` with **`Str(2024)` = `" 2024"`** (VBA `Str` prepends a space for non-negative numbers). Result: **`" 20241225"` — 9 chars with a LEADING SPACE**, not `"20241225"`.
- **Re-implementer guidance:** the whole year-replace step is redundant and harmful. The correct output is simply `Format(convDate(value), "yyyymmdd")` (bare 8 digits). **Verify how `Export.bas` / `Sheet1.ExportCreditRow` and the BCHDET `valueDate` field consume this** — if the export does not `Trim`, the emitted date field carries the leading space.
- **Exact I/O (as written, including the bug):**

  | input (`dd/mm/yyyy`) | `convDate` → Date | `Format …"yyyymmdd"` | returned |
  |---|---|---|---|
  | `"25/12/2567"` (พ.ศ.) | 2024-12-25 | `"20241225"` | `" 20241225"` |
  | `"25/12/2024"` (ค.ศ.) | 2024-12-25 | `"20241225"` | `" 20241225"` |
  | `"01/01/2569"` | 2026-01-01 | `"20260101"` | `" 20260101"` |

##### `convDate(str As String) As Date`
Parses a fixed-width `dd?mm?yyyy` string (separators at positions 3 & 6 are ignored) into a `Date`, converting Buddhist→Gregorian via `calYear`.
```vba
Dim day, month, year As Integer     ' NB: only `year` is Integer; day & month are Variant
day   = Int(Mid(str, 1, 2))
month = Int(Mid(str, 4, 2))
year  = calYear(Int(Mid(str, 7, 4)))
convDate = VBA.DateSerial(year, month, day)
```
- **Logic:** reads chars 1–2 (day), 4–5 (month), 7–10 (year); passes the year through `calYear`; builds the date with `DateSerial`.
- **Gotchas:** requires exactly the `NN?NN?NNNN` layout (10 chars). The `Dim day, month, year As Integer` declares only `year` as `Integer` (classic VBA trap; `day`/`month` are `Variant`). `day`/`month`/`year` shadow the VBA `Day`/`Month`/`Year` functions inside this scope.
- **I/O:** `"25/12/2567"` → `#2024-12-25#`; `"05/03/2024"` → `#2024-03-05#`.

##### `calYear(yearInput As Integer) As Integer` — the พ.ศ.↔ค.ศ. heuristic
```vba
If (yearInput <= year(Now) + 400) Then
    calYear = yearInput            ' assume already Gregorian (ค.ศ.)
Else
    calYear = yearInput - 543      ' assume Buddhist (พ.ศ.) → subtract 543
End If
```
- **Precise math:** threshold `T = Year(Now) + 400`. As of run-year 2026, `T = 2426`. Any year `≤ T` is treated as Gregorian and returned unchanged; any year `> T` is treated as Buddhist and has **543** subtracted (the Thai พ.ศ.→ค.ศ. offset).
- **Why +400:** a safety buffer so far-future Gregorian value dates still pass through, while real Buddhist years (2500s+) always exceed the threshold and convert.
- **Examples:**

  | input | branch | output |
  |---|---|---|
  | `2024` | ≤2426 | `2024` |
  | `2426` | ≤2426 (inclusive) | `2426` |
  | `2569` | >2426 | `2026` |
  | `2567` | >2426 | `2024` |
  | `2427` | >2426 | `1884` ← a genuine Gregorian 2427 would be wrongly converted (400 yrs out; irrelevant in practice) |

##### `removeDashSignPhoneNum(value As String) As String`
`removeDashSignPhoneNum = Replace(value, "-", "")` — strips dashes only. `"081-234-5678"` → `"0812345678"`. (Does not remove spaces or `+`.)

##### `removePeriod(value)` (untyped return → Variant)
`removePeriod = Replace(value, ".", "")` — strips all periods. Not referenced by the format path (dead/legacy; the period-strip in `convertAmountFormat` is commented out).

##### `checkEmptyString(value As String) As String`
Empty/`""` → `""`; otherwise → `convertAmountFormat(value)`. Used to blank out optional amount fields.

---

#### 1.3 Flag / conditional-value helpers (build the file's Y/N/E and optional-amount fields)

| Function | Signature | Returns |
|---|---|---|
| `checkRequiredFlag` | `(requiredFlag As Integer) As String` | `"Y"` if `=1`, else `"N"` |
| `checkFlagHaveValue` | `(value As String) As String` | `"N"` if empty/`""`, else `"Y"` |
| `checkFlagHaveEmailWHT` | `(email As String) As String` | `"N"` if empty/`""`, else **`"E"`** (WHT delivery = e-mail) |
| `checkValueWhenFlagIsNo` | `(flag As Long, value As Variant) As String` | `""` if `flag=0`, else `convertAmountFormat(CStr(value))` |
| `checkValueWhenFlagIsNoCount` | `(flag As Long, value As Variant) As String` | `""` if `flag=0`, else `CStr(value)` (no amount formatting — for counts) |
| `checkValueWhenFlagIsNoInvoice` | `(flag As Integer, value As Integer) As String` | `""` if `flag=0`, else `CStr(value)` |

- **Note:** `checkFlagHaveEmailWHT` returns `"E"` (not `"Y"`) — it encodes the WHT certificate delivery channel. `checkValueWhenFlagIsNo` vs `…Count` differ only in whether `convertAmountFormat` is applied (money vs integer count).

---

#### 1.4 Master-data lookups (dropdown-code resolution + error-message table)

##### `getMasterDataList(tableName As String) As String`
Returns a **formula string** pointing at column 1 of a `Master_data` ListObject, e.g. `"='Master_data'!$A$5:$A$12"`, used as a Data-Validation list source.
```vba
Set tableList = Sheets("Master_data").ListObjects(tableName)
sFormula = "='Master_data'!" & tableList.DataBodyRange.Columns(1).Address
getMasterDataList = sFormula
```
A large commented-out block shows an earlier implementation that read the values and `Join`ed them into a comma list — now dead.

##### `getCodeConstantsFromMasterData(typeConstants As String, indexOfDropList As Integer) As String`
Maps a dropdown's **selected 1-based index** to the code in column 2 of the `Master_data` table named `typeConstants`.
```vba
If IsEmpty(typeConstants) Or typeConstants = "" Then Exit Function   ' → ""
Set tbl = Worksheets("Master_data").ListObjects(typeConstants)
getCodeConstantsFromMasterData = tbl.DataBodyRange(indexOfDropList, 2).value
```
- **Edge:** no bounds check on `indexOfDropList`; a bad index raises a subscript error.

##### `getCodeConstantsFromMasterDataV2(typeConstants As String, matchString As String) As String`
Same table, but locates the row by **matching `matchString` against column 1** (via `IndexOf`), then returns column 2.
```vba
Index = IndexOf(tbl, matchString)
getCodeConstantsFromMasterDataV2 = tbl.DataBodyRange(Index, 2).value
```
- **Bug:** if `IndexOf` returns `0` (not found), `DataBodyRange(0, 2)` is an invalid row → runtime error. No not-found guard.

##### `IndexOf(coll As ListObject, item As Variant) As Long` (`Public`)
Returns the 1-based body-row index whose column-1 value equals `item`, else `0`.
```vba
For i = 1 To coll.range.Rows.count            ' iterates header + body rows
    If coll.DataBodyRange(i, 1).value = item Then IndexOf = i: Exit Function
Next
```
- **Bug:** the loop bound `coll.Range.Rows.count` **includes the header row**, but it indexes `DataBodyRange(i,1)` (body-only, header excluded). On a no-match table it reads `DataBodyRange(bodyCount+1, 1)` on the final iteration → one row past the body. This is a latent off-by-one; it happens to be masked whenever a match is found before the last iteration.

##### `FindErrorMessage(key As String) As String`
Looks up the `TBErrorMessage` table on `Master_data` (col1 = key → col2 = localized message); returns `""` if not found. `r` is an implicit `Variant` loop counter.

---

#### 1.5 Error-marking / cell-decoration UI helpers

These paint cells red (error) / yellow (warning/duplicate) / white (valid) and maintain the running error count in `Payment!N1`.

##### `MsgBoxInvalid(msg As String)` — `MsgBox msg, vbCritical`.

##### `CountErrorMsg(num As Integer)`
Reads `Payment!N1`, adds `num`, writes back:
```vba
CountError = Worksheets("Payment").range(addressCountError).value
Worksheets("Payment").range(addressCountError).value = CInt(CountError) + num
```
Callers pass `+1` (new error) or `-1` (cleared error).

##### `getActiveSheet(Optional sheetname As String) As Worksheet`
Returns `ThisWorkbook.Sheets(sheetname)`, defaulting `sheetname` to `"Payment"` when `""`.

##### `validCell(row, col, Optional sheetname)`
Clears an error mark on one cell:
```vba
If ws.Cells(row, col).Interior.Color = vbRed Then CountErrorMsg -1   ' decrement error count
ws.Cells(row, col).ClearComments
If ws.Cells(row, 1).Interior.Color = vbYellow Then
    ws.Cells(row, col).Interior.ColorIndex = 27      ' row flagged yellow → keep yellow
Else
    ws.Cells(row, col).Interior.ColorIndex = 2       ' else white
End If
```
- ColorIndex legend used throughout: **3 = red (error)**, **27 = yellow (warning/duplicate)**, **2 = white (clean)**.

##### `InvalidCell(row, col, msg, Optional sheetname)`
Marks one cell as an error:
```vba
If ws.Cells(row, col).Interior.Color <> vbRed Then CountErrorMsg 1   ' first-time error → increment
errMsg = FindErrorMessage(msg)                                        ' errMsg is an IMPLICIT global
ws.Cells(row, col).Interior.ColorIndex = 3
ws.Cells(row, col).ClearComments
If errMsg <> "" Then ws.Cells(row, col).AddComment errMsg _
                Else ws.Cells(row, col).AddComment msg
ws.Cells(row, col).Comment.Shape.TextFrame.AutoSize = True
```
- Side-effects: colours cell red, attaches a comment (mapped message if the `msg` key exists in `TBErrorMessage`, else the raw `msg`), increments error count only on the red-transition. `errMsg` is undeclared (implicit module-scope `Variant`, shared across calls).

##### `forceValidRow(sheetname As String, row As Integer)`
Clears every column in a row by calling `validCell`. Column count via `Cells(idxHeader+1, Columns.Count).End(xlToLeft).Column` for Payment, else `Cells(1, …)`. **Uses unqualified `Cells`** (operates on ActiveSheet, not necessarily `sheetname`).

##### `validRow(row, Optional sheetname)`
`ws.Rows(row).ClearComments` + set whole row `ColorIndex = 2` (white). Whole-row reset.

##### `invalidRow(row, cols As Collection, Optional sheetname)`
Paints the whole row **yellow** (27) except cells already red:
```vba
lastCol = ws.Cells(header, Columns.count).End(xlToLeft).Column   ' header=idxHeader for Payment else 1
For i = 1 To lastCol
    If ws.Cells(row, i).Interior.Color <> vbRed Then ws.Cells(row, i).Interior.ColorIndex = 27
Next i
```
- **Dead param:** `cols` is never used.

---

#### 1.6 Row / sequence-number utilities

##### `findRowByKey(ws, key, range As String) As Integer`
`Range(range).Find(What:=key)` → matched cell's row, or `0` if not found.

##### `findDuplicateRowsById(ws, key, range) As Collection`
Scans rows `1..lastRow` (lastRow from column A via `End(xlUp)`), collecting **every** row number where the first column of `range` (`Left(range,1)`) equals `key`. Returns a `Collection` of matching row indices (may be empty).

##### `findDuplicateRow(ws, key, range) As Integer`
Scans `firstRow(=2)..lastRow`; counts matches of `key` in column `Left(range,1)`; **returns the row number of the 2nd occurrence** (the moment `CountDuplicateRow > 1`), else `0`. This is the duplicate-detector used by `findCreditSeq`.

##### `findCreditSeq(row As Integer, typeSheet As String) As String`
```vba
seqNumber = Worksheets("Payment").Cells(row, 1).value
row = findDuplicateRow(Worksheets(typeSheet), seqNumber, "B:B")
findCreditSeq = IIf(row > 0, "Y", "N")   ' (written as If/Else)
```
Answers "does Payment row's credit-seq appear (as a duplicate) in the INV/WHT sheet's column B?" → `"Y"`/`"N"`. Note it reuses the `row` parameter as a scratch variable.

##### `genSeqNo(range As String) As Collection`
Finds the last used row & next seq number on the **Payment** sheet.
```vba
lastRow = .range(range).Find(What:="*", SearchOrder:=xlByRows, SearchDirection:=xlPrevious).row
If lastRow = idxHeader Then lastSeqNo = 0 Else lastSeqNo = .range(Left(range,1) & lastRow).value
res.Add lastRow : res.Add lastSeqNo + 1        ' → [lastRow, nextSeqNo]
```
`Const firstRow = 10` here is **dead** (unused).

##### `autoGenSeqNo(cell As range) As Integer` (returns a Boolean-as-Integer success flag)
Auto-fills column A of the Payment sheet with the next sequence number when a new record row is started:
```vba
Set resGenSeqNo = genSeqNo("A:A")           ' [lastRow, nextSeq]
If IsEmpty(Worksheets("Payment").Cells(cell.row, 1)) Then
    If cell.row < resGenSeqNo.item(1) Then
        MsgBox "Row of record shouldn't be less then last record." : checkSuccess = False
    ElseIf cell.row = (resGenSeqNo.item(1) + 1) Then
        Worksheets("Payment").Cells(cell.row, 1).value = resGenSeqNo.item(2)   ' assign next seq
    Else
        MsgBox "Record shouldn't have space between row."
        Worksheets("Payment").Cells(cell.row, cell.Column).ClearContents : checkSuccess = False
    End If
End If
autoGenSeqNo = checkSuccess
```
Enforces contiguous, monotonically-increasing record rows on Payment. Returns success (`True`/`False` coerced to Integer).

##### `autoGenSeqNoWHTandINV(cell As range) As Integer` — **buggy / likely dead**
A near-copy of `autoGenSeqNo` but **mixing sheets**: it reads `genSeqNo("A:A")` (Payment), writes the seq into `Worksheets("WHT").Cells(cell.row, 1)`, and on the assign branch fires a stray `MsgBox "Please"` (debug leftover). The `ClearContents` in the else-branch still targets the **Payment** sheet. Inconsistent target sheets → treat as broken/dead; do not port as-is.

##### `checkCreditSeqNo(cell As range)` (no declared return)
If Payment column A at `cell.row` is empty → `MsgBox "Please input credit seq no"`. Computes `genSeqNo` but never uses it. No return value assigned.

##### `checkLimitValue(key, limit As Integer, currentRow As Integer, collumn As Integer) As Boolean`
Windowed count of `key` occurrences, intended to cap how many rows may share a key (e.g. max WHT income lines).
```vba
startRow = currentRow - limit - 1 : If startRow <= 0 Then startRow = 1
countValue = 0
For row = startRow To currentRow
    If ActiveSheet.Cells(row, collumn).value = key Then countValue = countValue + 1
Next row
If countValue < limit Or Not IsEmpty(ActiveSheet.Cells(currentRow, collumn)) Then
    checkLimitValue = True Else checkLimitValue = False
```
- **Questionable logic:** the `Or Not IsEmpty(current cell)` clause makes it return `True` almost whenever the current cell is populated, largely defeating the "< limit" cap. Uses `ActiveSheet` (unqualified). Window spans `currentRow-limit-1 .. currentRow` (i.e. `limit+2` rows).

---

#### 1.7 Aggregation functions (feed the batch totals + nested-record counts)

##### `calculateNumberOfCreditAndAmount(targetWorkSheet, indexOfKeyValue, startIndexRecordRow, indexOfTargetValue) As Collection`
Walks rows from `startIndexRecordRow` until the key column is empty, counting rows and summing the target column. Returns `Collection` **[count, sum]**.
```vba
Do Until IsEmpty(targetWorkSheet.Cells(iRow, indexOfKeyValue))
    countNumberOfCreditByCusRef = countNumberOfCreditByCusRef + 1
    sumAmountByCusRef = sumAmountByCusRef + targetWorkSheet.Cells(iRow, indexOfTargetValue)
    iRow = iRow + 1
Loop
returnModel.Add countNumberOfCreditByCusRef : returnModel.Add sumAmountByCusRef
```
- **Note:** the per-key filter (`If key.value = …`) is **commented out**, so it counts/sums **every** non-empty row from the start index — used to compute the batch's `creditCount` and `totalAmount`.

##### `countAndSumInvoice(seq As String) As Collection`
Only runs when the **`InvoiceChk`** checkbox on the ActiveSheet = 1. Iterates the `Invoice` sheet from row 2 until column 2 is empty; for rows whose **col 2 = seq** (credit seq), accumulates count, `col 5` (invoice amount), `col 8` (VAT), and sets `checkRequired = 1`. Returns **[numberOfInvoiceDetail, totalInvoiceAmount, totalVatAmount, checkRequired]**.
- **Magic columns to preserve:** Invoice seq = col 2, amount = col 5, VAT = col 8.

##### `countAndSumWHT(seq As String) As Collection`
Only runs when the **`WHTChk`** checkbox = 1. Iterates `WHT` from row 2 until col 2 empty; for **col 2 = seq**, sums the **five** income-detail tax-amount columns and counts the certificate:
```vba
totalWHTAmount = totalWHTAmount _
  + Cells(iRow,30) + Cells(iRow,30+8) + Cells(iRow,30+8+8) _
  + Cells(iRow,30+8+8+8) + Cells(iRow,30+8+8+8+8)     ' cols 30,38,46,54,62
```
Returns **[numberOfWHTCert, totalWHTAmount, checkRequired]**.
- **Magic columns:** WHT seq = col 2; the 5 WHT income blocks are 8 columns apart with the tax-amount at columns **30, 38, 46, 54, 62** (matches the "up to 5 income-detail blocks" in `Sheet4.ExportWHTRow`).

##### `getRecipientAddress(flag As Integer, seq As String) As String`
`flag=0` → `""`. Otherwise scans `WHT` from row 2 until col 2 empty; on **col 2 = seq** returns **col 11** (recipient address) via `Exit Function`; if never matched, falls through to `getRecipientAddress = ""`.

---

#### 1.8 Collection / misc utilities

##### `ExistsIn(item As Variant, lots As Collection) As Boolean`
Linear membership test (`For Each e In lots: If item = e Then True`).

##### `CollectionToArray(c As Collection, Optional StartIdx As Long, Optional Size As Long) As Variant`
Copies a collection into a `Variant()` array.
```vba
If Size < c.count Then Size = c.count
ReDim A(StartIdx To StartIdx + Size - 1)
For Each Ci In c : A(i) = Ci : i = i + 1 : Next
```
- **Bug:** the write index `i` starts at **0**, ignoring `StartIdx`. When `StartIdx > 0`, `A(0)` is below the array's lower bound → subscript error. Correct only for the default `StartIdx = 0`.

##### `compareDateWithCurrentDate(dateString As String) As Boolean` — **dead**
Computes `dateInput`/`dateCurrent` but the actual comparison and the return assignment are entirely commented out → always returns `False` (default). Also `CDate(Format(dateString, "dd/mm/yyyy"))` is a questionable round-trip. Not usable as-is.

##### `checkValue() As Integer` — **empty stub** (no body, returns 0).

##### `generateCustomerBatchReferanceName() As String` / `generateCustomerFileReferance() As String`
Both identical:
```vba
= Format(Now(), "DDMMYYHHMMSS")
```
- **Format decode:** VBA `Format` is context-sensitive — `MM` after `HH` means **minutes**. So the token stream is Day-Month-Year(2)-Hour-Minute-Second, e.g. `"310826193045"` = 31 Aug 26, 19:30:45. Both the batch ref and file ref use the same timestamp scheme (12 digits).

---

#### 1.9 Complete `Util.bas` procedure inventory (quick index)

Format/convert: `convertAmountFormat`, `convertDateFormat`, `convDate`, `calYear`, `removePeriod`, `removeDashSignPhoneNum`, `checkEmptyString` · Flags: `checkRequiredFlag`, `checkFlagHaveValue`, `checkFlagHaveEmailWHT`, `checkValueWhenFlagIsNo`, `checkValueWhenFlagIsNoCount`, `checkValueWhenFlagIsNoInvoice` · Master-data: `getMasterDataList`, `getCodeConstantsFromMasterData`, `getCodeConstantsFromMasterDataV2`, `IndexOf`, `FindErrorMessage` · Cell UI/errors: `MsgBoxInvalid`, `CountErrorMsg`, `getActiveSheet`, `validCell`, `InvalidCell`, `forceValidRow`, `validRow`, `invalidRow` · Rows/seq: `findRowByKey`, `findDuplicateRowsById`, `findDuplicateRow`, `findCreditSeq`, `genSeqNo`, `autoGenSeqNo`, `autoGenSeqNoWHTandINV`, `checkCreditSeqNo`, `checkLimitValue` · Aggregation: `calculateNumberOfCreditAndAmount`, `countAndSumInvoice`, `countAndSumWHT`, `getRecipientAddress` · Misc: `ExistsIn`, `CollectionToArray`, `compareDateWithCurrentDate`, `checkValue`, `generateCustomerBatchReferanceName`, `generateCustomerFileReferance`.

---

### 2. `ThisWorkbook.bas` (~74 lines) — workbook events

#### 2.1 Module-level state
```vba
Public paymentRowToValidate As Integer
Public invoiceRowToValidate As Integer
Public whtRowToValidate As Integer
```
Three globals that remember the previously-active row per sheet (Payment/Invoice/WHT) so a selection-change handler can decide whether the user left a row.

#### 2.2 `Workbook_Open()`
```vba
Sub Workbook_Open()
    'PreventInsertDeleteRowsCols          ' commented out
    If (ActiveSheet.Name = "Payment") Then
        Call Sheet1.checkProdRadio
    End If
End Sub
```
- **Only initialisation performed:** if the workbook opens on the Payment sheet, it calls `Sheet1.checkProdRadio` (syncs the product-type radio/product-code UI). No sheet-protection code runs here; the `PreventInsertDeleteRowsCols` line is a commented-out no-op.

#### 2.3 `Workbook_SheetSelectionChange(ByVal Sh As Object, ByVal Target As range)`
- Guards: `If Target.Cells.count > 1 Then Exit Sub` (ignores multi-cell selections).
- Per active sheet, it swaps the remembered "previous row" into `rowActive` and stores the new `ActiveCell.row`:
```vba
Select Case ActiveSheet.Name
    Case "Payment": rowActive = paymentRowToValidate : paymentRowToValidate = ActiveCell.row
    Case "Invoice": rowActive = invoiceRowToValidate : invoiceRowToValidate = ActiveCell.row : rowHeader = 1
    Case "WHT":     rowActive = whtRowToValidate    : whtRowToValidate    = ActiveCell.row : rowHeader = 1
    Case Else:      Exit Sub
End Select
```
- **All validation is disabled:** the subsequent `If (rowActive > 1) And (rowActive <> ActiveCell.row)` block's bodies — the calls to `ValidDebitMandatory` / `ValidateRowInfo(rowActive)` — are **entirely commented out**. So today this handler only maintains the row-tracking globals and performs no validation. (It uses external `idxHeader` in one of the commented branches.)

#### 2.4 `Workbook_NewSheet(ByVal Sh As Object)` (`Private`)
```vba
Application.DisplayAlerts = False
Sh.Delete
```
- **Protection behaviour:** any newly-inserted sheet is silently deleted (alerts suppressed). This is the only active structural protection in this module — the workbook is locked to its fixed 6-sheet layout.

#### 2.5 Dead code
`Workbook_SheetBeforeDoubleClick` (which would set `Cancel = True` to block double-click editing) is present only as a fully commented-out block.

---

### 3. Empty worksheet code-behind modules — `Sheet5.bas`, `Sheet6.bas`, `Sheet8.bas`

Each is **299 bytes / 8 lines** and contains **only the standard VBA class attribute header — no procedures, no code**:
```vba
Attribute VB_Name = "Sheet5"     ' (…"Sheet6" / "Sheet8")
Attribute VB_Base = "0{00020820-0000-0000-C000-000000000046}"   ' Excel Worksheet class GUID
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = True
Attribute VB_TemplateDerived = False
Attribute VB_Customizable = True
```
- The `VB_Base` GUID `{00020820-…}` is Excel's **Worksheet** class (contrast `ThisWorkbook`'s `{00020819-…}` Workbook class), confirming these are worksheet code-behind modules with no logic. `Sheet5`/`Sheet6` are the code names for `Master_data`/`File_Info`; `Sheet8` is a code name with no live-visible tab (a hidden/vestigial sheet). Nothing to re-implement — they hold no behaviour.

---

### 4. `UserForm1.bas` — empty, unused UserForm (recovered)

The extractor originally emitted only the 40-byte placeholder `<<decompress error: index out of range>>`. **That was an extractor bug**, not a corrupt module: the OLE directory has two entries named `UserForm1` — a 1190-byte **code stream** (type 2) and an empty **form storage** (type 1, holding `f`/`o`/`\x01CompObj`/`\x03VBFrame`). The extractor's `byname` dict overwrote the code stream with the empty storage and then read 0 bytes. Decompressing the correct stream at module offset 959 yields the real (trivial) source:

```vba
Attribute VB_Name = "UserForm1"
Attribute VB_Base = "0{429297F0-AFB4-4F75-BC56-A521D954949A}{58C83BF1-5DB9-48DF-AA64-5353A76997D5}"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
Attribute VB_TemplateDerived = False
Attribute VB_Customizable = False
```
- **The module has no code** — only the attribute header (two blank lines follow). No event handlers, no methods.
- The form designer metadata (`\x03VBFrame` stream) shows a default, **control-less** MS-Forms 2.0 form:
  ```
  Begin {C62A69F0-16DC-11CE-9E98-00AA00574A4F} UserForm1
     Caption         =   "UserForm1"
     ClientHeight    =   3012
     ClientLeft      =   120
     ClientTop       =   468
     ClientWidth     =   4560
     StartUpPosition =   1  'CenterOwner
  End
  ```
  The `f` (form) stream is 58 bytes with no embedded controls, and the `o` (object) stream is empty.
- **Conclusion:** `UserForm1` is a leftover blank default UserForm — no controls, no code, never shown, not referenced anywhere in the project. **Dead code**; a re-implementation should omit it entirely.

---

#### Cross-file dependency notes for the master document
- `Util.convertAmountFormat` and `Util.convertDateFormat` are the two functions that produce the pipe file's amount and date fields; **the `convertDateFormat` leading-space bug (Section 1.2) must be reconciled against `Export.bas`/`Sheet1.ExportCreditRow`** (whoever documents those should confirm whether the date is `Trim`-med before it lands in BCHDET `valueDate`/TXNDET).
- `Util.calculateNumberOfCreditAndAmount`, `countAndSumInvoice`, `countAndSumWHT`, `getRecipientAddress` supply the batch-total and nested INVDET/WHTCER counts consumed by the export routines; the **magic column indices** (Invoice 2/5/8; WHT 2/11 and tax-amount cols 30/38/46/54/62) are load-bearing and must be preserved.
- `Util` depends on external `idxHeader` and `Sheet1.checkProdRadio`; `ThisWorkbook.Workbook_Open` is the sole caller of `checkProdRadio`.