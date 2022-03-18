/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_DiscountDel] 
	@DiscountGroupId INT, 
	@ErrCode INT = 0 OUTPUT, 
	@ErrMsg VARCHAR(4000) = '' OUTPUT
AS
/*  
	 Created: 20180705@Parsons [#94282]
	 Task: Enhance Manage Discount group function to support more discount schemes
	 DB: DBCUST.bodb_licensee   

	 Revisions:  
		- 20180705@Parsons: Delete discount groups [#94282]
		- 20211101@Percy: Remove useless params [RedmineID: #162158]
	 
	 Params:

	 Explannation: 
*/

BEGIN
	SET NOCOUNT ON

	--remove assignment
	DELETE dbo.LA_DiscountGroupAssignment WITH(ROWLOCK)
	WHERE DiscountGroupId = @DiscountGroupId
	IF @@ERROR > 0
	BEGIN
		SELECT @ErrMsg = 'Delete failed. Please try again.', @ErrCode = 516
		RETURN
	END

	--remove product
	DELETE dbo.LA_DiscountGroupProduct WITH(ROWLOCK)
	WHERE DiscountGroupId = @DiscountGroupId
	IF @@ERROR > 0
	BEGIN
		SELECT @ErrMsg = 'Delete failed. Please try again.', @ErrCode = 516
		RETURN
	END

	--remove currency
	DELETE dbo.LA_DiscountGroupCurrency WITH(ROWLOCK)
	WHERE DiscountGroupId = @DiscountGroupId
	IF @@ERROR > 0
	BEGIN
		SELECT @ErrMsg = 'Delete failed. Please try again.', @ErrCode = 516
		RETURN
	END

	--remove detail
	DELETE dbo.LA_DiscountGroupDetail WITH(ROWLOCK)
	WHERE DiscountGroupId = @DiscountGroupId
	IF @@ERROR > 0
	BEGIN
		SELECT @ErrMsg = 'Delete failed. Please try again.', @ErrCode = 516
		RETURN
	END

	--remove header
	DELETE dbo.LA_DiscountGroupHeader WITH(ROWLOCK)
	WHERE DiscountGroupId = @DiscountGroupId
	IF @@ERROR > 0
	BEGIN
		SELECT @ErrMsg = 'Delete failed. Please try again.', @ErrCode = 516
		RETURN
	END
END
GO
