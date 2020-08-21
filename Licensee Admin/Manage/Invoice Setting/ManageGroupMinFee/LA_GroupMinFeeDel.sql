/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_GroupMinFeeDel] 
	@GroupMinFeeId INT, 
	@UserId INT, 
	@LoginIp VARCHAR (50)	= '', 
	@ErrCode INT = 0 OUTPUT, 
	@ErrMsg VARCHAR(4000) = '' OUTPUT
AS
/*  
	 Created: 20200703@Mason [#134492]
	 Task: Delete group min fee
	 DB: DBCUST.bodb_licensee   

	 Revisions:  
		- 20200703@Mason: Implement Group Min Fee [#134492]
	 
	 Params:

	 Explannation: 
*/

BEGIN
	SET NOCOUNT ON

	-- Remove party assignment in group
	DELETE dbo.LA_GroupMinFeeAssignment WITH(ROWLOCK)
	WHERE GroupMinFeeID = @GroupMinFeeId
	IF @@ERROR > 0
	BEGIN
		SELECT @ErrMsg = 'Delete failed. Please try again.', @ErrCode = 516
		RETURN
	END

	-- Remove fee setting
	DELETE dbo.LA_GroupMinFeeDetail WITH(ROWLOCK)
	WHERE GroupMinFeeID = @GroupMinFeeId
	IF @@ERROR > 0
	BEGIN
		SELECT @ErrMsg = 'Delete failed. Please try again.', @ErrCode = 516
		RETURN
	END

	-- Remove group header
	DELETE dbo.LA_GroupMinFeeHeader WITH(ROWLOCK)
	WHERE GroupMinFeeID = @GroupMinFeeId
	IF @@ERROR > 0
	BEGIN
		SELECT @ErrMsg = 'Delete failed. Please try again.', @ErrCode = 516
		RETURN
	END
END
GO