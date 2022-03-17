/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

CREATE PROCEDURE dbo.LA_VendorPaymentSettingSel
	@ProductIDs VARCHAR(1000)
AS
/*  
	Created: 20220324@Danny
	Task : Get all vendor payment settings
	DB: DBLIC.bodb_Licensee
	
	Revisions:     
		- 20220324@Danny: Create SP [RedmineID: #168387]
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @tmpProducts TABLE (ProductID INT, ProductName VARCHAR(50)) 
	INSERT INTO @tmpProducts (ProductID)
	SELECT DISTINCT value FROM STRING_SPLIT(@ProductIDs, ',')

	UPDATE		t
	SET			t.ProductName = CASE WHEN t.ProductID = 1000 THEN 'Bet Builder'
									 WHEN t.ProductID = 1001 THEN 'Muay Thai' ELSE p.ProductName END
	FROM		@tmpProducts t
	LEFT JOIN	dbo.Product3rd p ON p.ProductId = t.ProductID
	
	SELECT		la.ProductId, tmp.ProductName, la.ReportFunctionKey, la.TemplateID, la.TimezoneIDs, la.IsConvertNegativeFeeToZero, la.IsConvertNegativePaytoSupplierToZero, la.IsActive
	FROM		dbo.LA_VendorPaymentSetting la WITH(NOLOCK)
	INNER JOIN	@tmpProducts tmp ON la.ProductId = tmp.ProductID
	ORDER BY	la.ProductID

END
GO
