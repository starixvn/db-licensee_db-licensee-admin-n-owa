
-- Product list
exec LA_VendorPaymentProductListSel_UAT1

-- 3rd winloss report func
exec LA_VendorPaymentFunctionKeySel_UAT1

-- Setting Select
exec LA_VendorPaymentSettingSel_UAT1
	@ProductIDs = '2,5,8,10,15,21,22,23,24,25,27,28,31,32,34,36,39,40,45,46,47,49,50,51,52,55,56,57,59,60,61,62,65,67,68,69,1000,1001'

-- Setting Modify
DECLARE @ErrCode INT = 0, 
	    @ErrMsg  NVARCHAR(1000) = ''

exec dbo.LA_VendorPaymentSetting_Modify_UAT1
	@ProductID												 = 1001,
	@ReportFunctionKey										= 'vendorpayment_MuayThai',
	@TemplateID												= 12,
	@TimezoneIDs											= '1',
	@IsConvertNegativeFeeToZero								= 0,
	@IsConvertNegativePaytoSupplierToZero					= 0, -- 0
	@IsActive												= 0,
	@ErrCode												= @ErrCode	OUTPUT,
	@ErrMsg													= @ErrMsg	OUTPUT

	SELECT @ErrCode, @ErrMsg

