/*<info serverAlias="DBLIC-bodb_Licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
CREATE PROCEDURE [dbo].[SH_VendorSettingSel_NonConfigurable]
	@ProductIDs		VARCHAR(MAX) = ''
AS
/*
	Created: 20250627@Danny
	Task : Get Vendor setting (Pay to supplier)  Non-Configurable
	DB: DBLIC.bodb_Licensee

	Revisions:
		- 20250627@Danny: Initialize [Redmine: #212221]

	EXEC SH_VendorSettingSel_NonConfigurable '2,5,8,22,27,28,31,34,36,39,40,77'
		
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @tmp_product TABLE (ProductID INT)  

	INSERT INTO @tmp_product(ProductID)
	SELECT CAST(Value AS INT) 
	FROM   STRING_SPLIT(@ProductIDs,',')

	SELECT   vw.ProductID
			,CASE WHEN vw.ProductID = 1000 THEN 'Bet Builder'
			      WHEN vw.ProductID = 1001 THEN 'Muay Thai'
			 ELSE p3.ProductName END AS ProductName
			,vw.BillingTerms
			, p3.EndOfSupportDate
	FROM   vw_SH_VendorSettingSel_NonConfigurable vw
	INNER JOIN @tmp_product tp ON vw.ProductID = tp.ProductID
	LEFT JOIN Product3rd p3 WITH(NOLOCK) ON vw.ProductID = p3.Productid

END
GO