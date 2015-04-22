USE bodb_licensee
GO
ALTER PROCEDURE dbo.LA_DiscountGroupDel @DiscountId INT
	, @UserId INT
	, @LoginIp VARCHAR (50)	= ''

	, @ErrCode INT = 0 OUTPUT
	, @ErrMsg VARCHAR(4000) = '' OUTPUT
	, @GroupIdOut SMALLINT = 0 OUTPUT
AS
/*  
	 Created: 20150422@Patrick
	 Task : Delete discount group
	 DB: DB052.bodb_Licensee
	 Revisions:     
		
	 Params:
*/
BEGIN
	SET NOCOUNT ON
	--validate this discount has applied to Invoice yet
	DECLARE @PayerIdList VARCHAR(4000)
	SELECT COALESCE(@PayerIdList + ',' + CAST(a.PartyId AS VARCHAR), CAST(a.PartyId AS VARCHAR))
	FROM dbo.LA_DiscountGroupAssignment a WITH(NOLOCK)
	WHERE DiscountGroupId = @DiscountId

	IF ISNULL(@PayerIdList, '') <> ''
	BEGIN
		EXEC dbo.LA_Discount_ValidatePayerAssignment @DiscountId = @DiscountId
			, @PayerIdList  = @PayerIdList
			, @Mode = 'R'

			, @ErrCode = @ErrCode OUTPUT
			, @ErrMsg = @ErrMsg OUTPUT
		IF @ErrCode > 0
		BEGIN
			SELECT @ErrMsg = 'Cannot delete the group, it is being applied.', @ErrCode = 515
			RETURN
		END
	END

	--remove assignment
	DELETE dbo.LA_DiscountGroupAssignment WITH(ROWLOCK)
	WHERE DiscountGroupId = @DiscountId
	IF @@ERROR > 0
	BEGIN
		SELECT @ErrMsg = 'Delete failed. Please try again.', @ErrCode = 516
		RETURN
	END

	--remove product
	DELETE dbo.LA_DiscountGroupProduct WITH(ROWLOCK)
	WHERE DiscountGroupId = @DiscountId
	IF @@ERROR > 0
	BEGIN
		SELECT @ErrMsg = 'Delete failed. Please try again.', @ErrCode = 516
		RETURN
	END

	--remove detail
	DELETE dbo.LA_DiscountGroupDetail WITH(ROWLOCK)
	WHERE DiscountGroupId = @DiscountId
	IF @@ERROR > 0
	BEGIN
		SELECT @ErrMsg = 'Delete failed. Please try again.', @ErrCode = 516
		RETURN
	END

	--remove header
	DELETE dbo.LA_DiscountGroupHeader WITH(ROWLOCK)
	WHERE DiscountGroupId = @DiscountId
	IF @@ERROR > 0
	BEGIN
		SELECT @ErrMsg = 'Delete failed. Please try again.', @ErrCode = 516
		RETURN
	END

END
GO
