/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_RebateDel] 
	@GroupId INT, 
	@UserId INT, 
	@LoginIp VARCHAR (50)	= '', 
	@ErrCode INT = 0 OUTPUT, 
	@ErrMsg VARCHAR(4000) = '' OUTPUT
AS
/*  
	 Created: 20180525@Parsons [#94282]
	 Task : Enhance Manage Discount group function to support more discount schemes
	 DB: DBCUST.bodb_licensee   

	 Revisions:  
		- 20180525@Parsons: Delete rebate group [#94282]
		- 20190510@Percy: Migrate to DBCUST.bodb_Licensee [RedmineID: #103658]

	 Params:

	 Explannation: 
*/

BEGIN
	SET NOCOUNT ON
	DECLARE @startRun DATETIME, @endRun DATETIME, @duration INT, @logSPData VARCHAR(MAX)
		, @logSPDataOld	VARCHAR(MAX), @xml XML
	SET @startRun = GETDATE()

	--get old data for write log
	SET @xml = (
			SELECT DiscountGroupId AS '@gd'
				, DiscountGroupName AS '@gn'
				, CurrencyId AS '@c'
				, FromDate AS '@fd'
				, ToDate AS '@td'
				, DiscountGroupType AS '@dt'
				, Priority AS '@pr'
				, (SELECT DiscountGroupId AS '@dg'
					, FromAmount AS '@fam'
					, ToAmount AS '@tam'
					, Rate AS '@r'
				FROM dbo.LA_DiscountGroupDetail WITH(NOLOCK) WHERE DiscountGroupId = @GroupId
				FOR XML PATH('x'), TYPE)
				, (SELECT DiscountGroupId AS '@gd'
					, ProductId AS '@p'
				FROM dbo.LA_DiscountGroupProduct WHERE DiscountGroupId = @GroupId
				FOR XML PATH('y'), TYPE)
				, (SELECT DiscountGroupId AS '@gd'
					, PartyID AS '@pa'
				FROM dbo.LA_DiscountGroupAssignment WHERE DiscountGroupId = @GroupId
				FOR XML PATH('z'), TYPE)
			FROM dbo.LA_DiscountGroupHeader WITH(NOLOCK) WHERE DiscountGroupId = @GroupId
			FOR XML PATH('r'), TYPE)

	SET @logSPDataOld = REPLACE(CONVERT(VARCHAR(MAX), @xml), '" />', '"/"')

	--validate this rebate has applied to Invoice yet
	DECLARE @HasBilling BIT = 0
	EXEC LA_Rebate_HasBilling @GroupId = @GroupId, @HasBilling = @HasBilling OUTPUT

	IF (ISNULL(@HasBilling, 0) = 1)
	BEGIN
		SELECT @ErrMsg = 'Cannot delete the group, it is being applied.', @ErrCode = 515
		RETURN
	END

	--remove assignment
	DELETE dbo.LA_DiscountGroupAssignment WITH(ROWLOCK)
	WHERE DiscountGroupId = @GroupId
	IF @@ERROR > 0
	BEGIN
		SELECT @ErrMsg = 'Delete failed. Please try again.', @ErrCode = 516
		RETURN
	END

	--remove product
	DELETE dbo.LA_DiscountGroupProduct WITH(ROWLOCK)
	WHERE DiscountGroupId = @GroupId
	IF @@ERROR > 0
	BEGIN
		SELECT @ErrMsg = 'Delete failed. Please try again.', @ErrCode = 516
		RETURN
	END

	--remove detail
	DELETE dbo.LA_DiscountGroupDetail WITH(ROWLOCK)
	WHERE DiscountGroupId = @GroupId
	IF @@ERROR > 0
	BEGIN
		SELECT @ErrMsg = 'Delete failed. Please try again.', @ErrCode = 516
		RETURN
	END

	--remove header
	DELETE dbo.LA_DiscountGroupHeader WITH(ROWLOCK)
	WHERE DiscountGroupId = @GroupId
	IF @@ERROR > 0
	BEGIN
		SELECT @ErrMsg = 'Delete failed. Please try again.', @ErrCode = 516
		RETURN
	END

	--write log
	SET @endRun = GETDATE()
	SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun)

	-- Write Log
	EXEC CustDB.dbo.NAP_SpecialCustSetting_WriteLog_Wrapper
		@UserId			= @UserID
		,@IP			= @LoginIP
		,@LicenseeID	= 0
		,@CurrencyID	= 0
		,@SPName		= 'LA_RebateDel'
		,@CustId		= 0
		,@Duration		= @duration
		,@Data			= @logSPData
		,@OldData		= @logSPDataOld
END
GO
