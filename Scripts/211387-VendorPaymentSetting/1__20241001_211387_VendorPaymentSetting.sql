/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20241001@Danny
	DB: DBCUST.bodb_licensee
	Description: Update LA_function
*/


-- 
UPDATE  LA_Function WITH(ROWLOCK)
SET		FunctionKey = REPLACE(FunctionKey,'VendorPaymentInDetails_','VendorPaymentProductList_')
WHERE	FunctionKey LIKE '%VendorPaymentInDetails_%'

UPDATE  LA_VendorPaymentSetting  WITH(ROWLOCK) 
SET		ReportFunctionKey = REPLACE(ReportFunctionKey,'VendorPaymentInDetails_','VendorPaymentProductList_')
WHERE	ReportFunctionKey LIKE '%VendorPaymentInDetails_%'


GO
DECLARE @FunctionID INT, @ParentName NVARCHAR(100)

SELECT  @FunctionID = FunctionID, @ParentName = FunctionName  FROM LA_Function WITH(NOLOCK) WHERE FunctionKey = 'VendorPaymentProductList'

UPDATE  LA_Function WITH(ROWLOCK)
SET ParentID = @FunctionID , ParentName = @ParentName
WHERE FunctionKey LIKE '%VendorPaymentProductList_%'


