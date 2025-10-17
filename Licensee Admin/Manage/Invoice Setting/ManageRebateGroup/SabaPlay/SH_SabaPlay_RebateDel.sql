/*<info serverAlias="DBCUST-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
CREATE PROCEDURE [dbo].[SH_SabaPlay_RebateDel] 
	@GroupId INT, 
	@UserId INT, 
	@LoginIp VARCHAR (50)	= '', 
	@ErrCode INT = 0 OUTPUT, 
	@ErrMsg VARCHAR(4000) = '' OUTPUT
AS
/*  
	 Created: 20251017@Danny [#241642]
	 Task : Manage Rebate On winloss group (SabaPlay)
	 DB: DBCUST.bodb_licensee   

	 Revisions:  
		- 20251017@Danny: Create SP [#241642]

	 Params:

	 Explannation: 
*/

BEGIN
	SET NOCOUNT ON
	DECLARE @startRun DATETIME, @endRun DATETIME, @duration INT, @logSPData NVARCHAR(MAX), @RebateGroupType INT
		, @logSPDataOld	NVARCHAR(MAX), @actionID INT = 2402
	SET @startRun = GETDATE()

	SELECT @RebateGroupType = DiscountGroupType
	FROM dbo.LA_DiscountGroupHeader WITH(NOLOCK) WHERE DiscountGroupId = @GroupId

	--get old data for write log
	SELECT @logSPDataOld = (
		SELECT  ld.DiscountGroupName 'gs.gn', 
				FORMAT (ld.FromDate,'MMM dd, yyyy') 'gs.af', 
				FORMAT (ld.ToDate,'MMM dd, yyyy') 'gs.at',
				CAST (ldg.Rate * 100 AS VARCHAR(50)) + ' %' 'gs.r' ,
				'Rebate on Licensing WL' 'gs.rt',
				ld.Remark 'gs.rm',
				pig.val AS 'gs.pig',
				pig.pid AS 'gs.pid',
				pa.val AS 'gs.pa'
		FROM LA_DiscountGroupHeader ld WITH(NOLOCK) 
		INNER JOIN LA_DiscountGroupDetail ldg WITH(NOLOCK) ON ld.DiscountGroupId = ldg.DiscountGroupId
		CROSS APPLY (
			SELECT  STRING_AGG(op.PartyName,', ') AS val, STRING_AGG(CAST(lda.PartyID AS VARCHAR(50)),',') AS pid
			FROM	LA_DiscountGroupAssignment lda
			INNER JOIN	OAS_Party op WITH(NOLOCK) ON   lda.PartyID = op.PartyID
			WHERE ld.DiscountGroupId = lda.DiscountGroupId
		) pig
		CROSS APPLY 
		(
			SELECT STRING_AGG(p3.ProductName,', ') AS val
			FROM  LA_DiscountGroupProduct ldp WITH(NOLOCK)
			LEFT JOIN vw_SabaPlay_Products p3  ON ldp.ProductId = p3.Productid
			WHERE ld.DiscountGroupId = ldp.DiscountGroupId
		) pa
		WHERE ld.DiscountGroupId = @GroupId
		FOR JSON PATH, WITHOUT_ARRAY_WRAPPER 
	)

	--validate this rebate has applied to Invoice yet
	DECLARE @HasBilling BIT = 0
	EXEC LA_Rebate_HasBilling @GroupId = @GroupId, @HasBilling = @HasBilling OUTPUT

	IF (ISNULL(@HasBilling, 0) = 1)
	BEGIN
		SELECT @ErrMsg = 'Cannot delete the group, it is being applied.', @ErrCode = 515
		RETURN
	END

	--remove currency setting 
	IF @RebateGroupType IN (32,42)
	BEGIN
		DELETE dbo.LA_DiscountGroupCurrency WITH(ROWLOCK)
		WHERE DiscountGroupId = @GroupId
		IF @@ERROR > 0
		BEGIN
			SELECT @ErrMsg = 'Delete failed. Please try again.', @ErrCode = 516
			RETURN
		END
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
	EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
		@UserId			= @UserID
		,@IP			= @LoginIp
		,@SPName		= 'SH_SabaPlay_RebateDel'
		,@CustId		= @GroupId
		,@Duration		= @duration
		,@TrackingValue2 = @LogSPData
		,@TrackingValue = @LogSPDataOld
		,@ActionID		 = @actionID
END
GO
