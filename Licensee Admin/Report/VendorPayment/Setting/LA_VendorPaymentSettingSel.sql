/*<info serverAlias="DBCUST-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE dbo.LA_VendorPaymentSettingSel
	@ProductIDs VARCHAR(1000),
	@FromDate	DATE = NULL,
	@ToDate		DATE = NULL
AS
/*  
	Created: 20220324@Danny
	Task : Get all vendor payment settings
	DB: DBCUST.bodb_Licensee
	
	Revisions:     
		- 20220324@Danny: Create SP [RedmineID: #168387]
		- 20250110@Danny: Handle template by date range [RedmineID: #214829]
*/
BEGIN
	SET NOCOUNT ON

	
	DECLARE @tmpProducts TABLE (ProductID INT, ProductName VARCHAR(50), OrderNo INT) 
	INSERT INTO @tmpProducts (ProductID)
	SELECT DISTINCT value FROM STRING_SPLIT(@ProductIDs, ',')

	UPDATE		t
	SET			t.ProductName = CASE WHEN t.ProductID = 1000 THEN 'Bet Builder'
									 WHEN t.ProductID = 1001 THEN 'Muay Thai' ELSE p.ProductName END,
				t.OrderNo	  = CASE WHEN t.ProductID = 1000 THEN -1
									 WHEN t.ProductID = 1001 THEN -2 ELSE  t.ProductID END
	FROM		@tmpProducts t
	LEFT JOIN	dbo.Product3rd p ON p.ProductId = t.ProductID

	DECLARE @Result TABLE (
		ProductID INT,
		ProductName VARCHAR(50),
		ReportFunctionKey  NVARCHAR(50),
		ReportFunctionName  NVARCHAR(100),
		TemplateID SMALLINT,
		TimezoneIDs  VARCHAR(50),
		IsConvertNegativeFeeToZero BIT,
		IsConvertNegativePaytoSupplierToZero BIT,
		IsActive BIT
	)
	
	INSERT INTO @Result(ProductID,ProductName,ReportFunctionKey,ReportFunctionName,TemplateID,TimezoneIDs,IsConvertNegativeFeeToZero,IsConvertNegativePaytoSupplierToZero,IsActive)
	SELECT		tmp.ProductId, 
				tmp.ProductName, 
				ISNULL(la.ReportFunctionKey, '') ReportFunctionKey, 
				ISNULL(fc.FunctionName, '') ReportFunctionName, 
				ISNULL(la.TemplateID,'') TemplateID, 
				ISNULL(la.TimezoneIDs,'') TimezoneIDs, 
				ISNULL(la.IsConvertNegativeFeeToZero,'') IsConvertNegativeFeeToZero, 
				ISNULL(la.IsConvertNegativePaytoSupplierToZero,'') IsConvertNegativePaytoSupplierToZero, 
				ISNULL(la.IsActive,0) AS IsActive
	FROM		@tmpProducts tmp  
	LEFT JOIN	dbo.LA_VendorPaymentSetting la WITH(NOLOCK) ON la.ProductId = tmp.ProductID
	LEFT JOIN	dbo.LA_Function fc WITH(NOLOCK) ON fc.FunctionKey = la.ReportFunctionKey

	IF @FromDate IS NOT NULL AND @ToDate IS NOT NULL
	BEGIN
		UPDATE r
		SET r.TemplateID = t.TemplateID
		FROM @Result r
		INNER JOIN LA_f_VendorPaymentSetting_History() t ON r.ProductID = t.ProductID 
															AND @FromDate BETWEEN t.FromDate AND t.Todate
															AND @ToDate BETWEEN t.FromDate AND t.Todate
	END

	SELECT ProductID,ProductName,ReportFunctionKey,ReportFunctionName,TemplateID,TimezoneIDs,IsConvertNegativeFeeToZero,IsConvertNegativePaytoSupplierToZero,IsActive 
	FROM @Result
	ORDER BY ProductID

END
GO
