/*<info serverAlias="DBLIC-bodb_licensee,DBCUST-bodb_licensee" selecters="wsv_nap" isFunction="1" isNested="1"></info>*/
ALTER FUNCTION [dbo].[LA_f_VendorPaymentSetting_History]
(
)
RETURNS TABLE
AS

/*
	Created: 20250113@Danny
	DB: DBLIC-bodb_Licensee
	Task: LA - Vendor Payment Setting History

	Revisions:
		- 20250113@Danny: Initialize SP [RedmineID: #154992]
		- 20250808@Danny: Virtual Sports 2 - Offer Tournament Prize [#235167]
		- 20250808@Danny: Integrate Jackpot Prize for Playtech product [#233715]
*/

RETURN
	SELECT  65	AS ProductId ,	
			14 TemplateID	,
			'0,1' TimezoneIDs	, 
			CAST (1 AS BIT)	IsConvertNegativeFeeToZero , 
			CAST (0 AS BIT) IsConvertNegativePaytoSupplierToZero	, 
			CAST('1900-01-01' AS DATE) AS FromDate,
			CAST('2024-11-30'  AS DATE) AS  Todate

	UNION ALL

	SELECT  27	AS ProductId ,	
			1 TemplateID	,
			'1' TimezoneIDs	, 
			CAST (0 AS BIT)	IsConvertNegativeFeeToZero , 
			CAST (0 AS BIT) IsConvertNegativePaytoSupplierToZero	, 
			CAST('1900-01-01' AS DATE) AS FromDate,
			CAST('2025-07-31'  AS DATE) AS  Todate

	UNION ALL

	SELECT  100	AS ProductId ,	
			18 TemplateID	,
			'0,1' TimezoneIDs	, 
			CAST (1 AS BIT)	IsConvertNegativeFeeToZero , 
			CAST (0 AS BIT) IsConvertNegativePaytoSupplierToZero	, 
			CAST('1900-01-01' AS DATE) AS FromDate,
			CAST('2025-07-31'  AS DATE) AS  Todate

GO

