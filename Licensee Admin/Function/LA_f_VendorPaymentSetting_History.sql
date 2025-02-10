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
		20250113@Danny: Initialize SP [RedmineID: #154992]
*/

RETURN
	SELECT  65	AS ProductId ,	
			14 TemplateID	,
			'0,1' TimezoneIDs	, 
			CAST (1 AS BIT)	IsConvertNegativeFeeToZero , 
			CAST (0 AS BIT) IsConvertNegativePaytoSupplierToZero	, 
			CAST('1900-01-01' AS DATE) AS FromDate,
			CAST('2024-11-30'  AS DATE) AS  Todate
GO