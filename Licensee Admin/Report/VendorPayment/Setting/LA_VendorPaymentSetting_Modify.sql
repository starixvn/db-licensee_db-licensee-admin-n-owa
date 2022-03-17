/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

CREATE PROCEDURE dbo.LA_VendorPaymentSetting_Modify
	@ProductID								INT				,
	@ReportFunctionKey						VARCHAR(100)	= '',
	@TemplateID								SMALLINT		= NULL,
	@TimezoneIDs							VARCHAR(50)		= '',
	@IsConvertNegativeFeeToZero				BIT				= NULL,
	@IsConvertNegativePaytoSupplierToZero	BIT				= NULL,
	@IsActive								BIT				= 0,
	@ErrCode								INT				= 0		OUTPUT,
	@ErrMsg									NVARCHAR(1000)	= ''	OUTPUT
AS
/*  
	Created: 20220324@Danny
	Task : Modify vendor payment settings
	DB: DBLIC.bodb_Licensee
	
	Revisions:     
		- 20220324@Danny: Create SP [RedmineID: #168387]

	Param's Explanation:
		
*/
BEGIN
	SET NOCOUNT ON

	-- check if Product exists
	IF EXISTS(SELECT 1 FROM dbo.LA_VendorPaymentSetting WITH (NOLOCK) WHERE ProductId = @ProductID)
	BEGIN

		UPDATE dbo.LA_VendorPaymentSetting WITH (UPDLOCK, ROWLOCK)
		SET	
			ReportFunctionKey						= @ReportFunctionKey,
			TemplateID								= @TemplateID,
			TimezoneIDs								= @TimezoneIDs,
			IsConvertNegativeFeeToZero				= @IsConvertNegativeFeeToZero,
			IsConvertNegativePaytoSupplierToZero	= @IsConvertNegativePaytoSupplierToZero,
			IsActive								= @IsActive
		WHERE ProductId = @ProductID

		IF @@ERROR > 0
		BEGIN
			SELECT @ErrMsg = 'Update failed. Please try again.', @ErrCode = 100
			RETURN
		END
	END
	ELSE
	BEGIN
		INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) 
		VALUES (@ProductID, @ReportFunctionKey, @TemplateID, @TimezoneIDs, @IsConvertNegativeFeeToZero, @IsConvertNegativePaytoSupplierToZero, @IsActive)
		
		IF @@ERROR > 0
		BEGIN
			SELECT @ErrMsg = 'Insert failed. Please try again.', @ErrCode = 101
			RETURN
		END

	END

END
GO
