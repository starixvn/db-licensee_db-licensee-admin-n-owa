/*<info serverAlias="DBLIC-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/

CREATE PROCEDURE dbo.LA_VendorSettingProductListSel
	@IsConfigurable	BIT	= 0
AS
/*  
	Created: 20220324@Danny
	Task : Get all vendor products
	DB: DBLIC.bodb_Licensee
	
	Revisions:     
		- 20250627@Danny: Initialize [Redmine: #212221]

		EXEC LA_VendorSettingProductListSel 0

*/
BEGIN
	SET NOCOUNT ON

	; WITH t AS
	(
		SELECT	p.ProductID AS ProductID, p.ProductName AS ProductName
		FROM	dbo.Product3rd p WITH(NOLOCK)

		UNION ALL
		SELECT 1000 AS ProductID, 'Bet Builder' AS ProductName

		UNION ALL
		SELECT 1001 AS ProductID, 'Muay Thai' AS ProductName
	), u AS
	(
		SELECT t.ProductID, t.ProductName, CASE WHEN vw.ProductID IS NULL THEN 1 ELSE 0 END IsConfigurable
		FROM t
		LEFT JOIN vw_SH_VendorSettingSel_NonConfigurable vw ON t.ProductID = vw.ProductID 
	)
	SELECT ProductID, ProductName FROM u
	WHERE IsConfigurable = @IsConfigurable
	ORDER BY  ProductID
	

END
GO

