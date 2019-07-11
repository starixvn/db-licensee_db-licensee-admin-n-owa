/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE dbo.LA_Discount_HasBilling
	@DiscountGroupId INT
	, @HasBilling BIT = 0 OUTPUT
AS
/*  
	 Created: 20150422@Patrick
	 Task: Check this discount has not belong to any a invoice yet
	 DB: DBCUST.bodb_Licensee
	 
	 Revisions:
		- 20150422@Patrick: Initialize SP
		
	 Params:
		+ @Mode : 
			- R: Remove, A: Add
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @PayerIdList VARCHAR(1024), @ErrCode INT
	SET @PayerIdList = NULL
	SELECT @PayerIdList = COALESCE(@PayerIdList + ',' + CAST(PartyId AS VARCHAR), CAST(PartyId AS VARCHAR))
	FROM dbo.LA_DiscountGroupAssignment a WITH(NOLOCK)

	EXEC dbo.LA_Discount_ValidatePayerAssignment @DiscountGroupId = @DiscountGroupId
		, @PayerIdList = @PayerIdList
		, @Mode = 'R'
		, @ErrCode = @ErrCode OUTPUT

	IF @ErrCode > 0
	BEGIN
		SELECT @HasBilling = 1
	END
	ELSE
	BEGIN
		SELECT @HasBilling = 0
	END

END
GO