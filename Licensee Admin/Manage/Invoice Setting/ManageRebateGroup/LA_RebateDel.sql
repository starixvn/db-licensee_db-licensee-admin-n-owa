/*<info serverAlias="DBCUST-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
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
		- 20230417@Danny: Insert new log with more information [#FeatureID 175125]
		- 20240613@Danny: Rebate on specific currencies [#FeatureID 206143]
		- 20250102@Danny: Rebate on Licensing winloss for specific currencies [RedmineID: #214767]

	 Params:

	 Explannation: 
*/

BEGIN
	SET NOCOUNT ON
	DECLARE @startRun DATETIME, @endRun DATETIME, @duration INT, @logSPData NVARCHAR(MAX), @RebateGroupType INT
		, @logSPDataOld	NVARCHAR(MAX), @actionID INT = 1702
	SET @startRun = GETDATE()

	SELECT @RebateGroupType = DiscountGroupType
	FROM dbo.LA_DiscountGroupHeader WITH(NOLOCK) WHERE DiscountGroupId = @GroupId

	--get old data for write log
	SELECT @logSPDataOld = (
		SELECT  ld.DiscountGroupName 'gs.gn', 
				FORMAT (ld.FromDate,'MMM dd, yyyy') 'gs.af', 
				FORMAT (ld.ToDate,'MMM dd, yyyy') 'gs.at',
				CAST (ldg.Rate * 100 AS VARCHAR(50)) + ' %' 'gs.r' ,
				CASE WHEN ld.DiscountGroupType = 2 THEN 'Rebate on Licensing Fee for All Currencies'
					 WHEN ld.DiscountGroupType = 12 THEN 'Tier Rebate'
					 WHEN ld.DiscountGroupType = 22 THEN 'Rebate on Licensing WL'
					 WHEN ld.DiscountGroupType = 32 THEN 'Rebate on Licensing Fee for specific currencies'
				END 'gs.rt',
				ld.Remark 'gs.rm',
				pig.val AS 'gs.pig',
				pig.pid AS 'gs.pid',
				pa.val AS 'gs.pa',
				CASE WHEN @RebateGroupType IN (32,42) THEN ca.val ELSE 'All currencies' END AS 'gs.ca'
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
			SELECT STRING_AGG(CASE WHEN  ldp.ProductId = 0 THEN 'Sportsbook' ELSE p3.ProductName END,', ') AS val
			FROM  LA_DiscountGroupProduct ldp WITH(NOLOCK)
			LEFT JOIN Product3rd p3 WITH(NOLOCK) ON ldp.ProductId = p3.Productid
			WHERE ld.DiscountGroupId = ldp.DiscountGroupId
		) pa
		OUTER APPLY 
		(
			SELECT STRING_AGG(CASE WHEN lgc.CurrencyId = 142 THEN 'USDT' 
								   WHEN lgc.CurrencyId IN (96, 202, 206, 208,209) THEN e.Code + ' ('+ e.currency+ ')'
								   ELSE e.Code END,', ') AS val
			FROM  LA_DiscountGroupCurrency lgc WITH(NOLOCK)
			INNER JOIN CustDB.dbo.Exchange e WITH(NOLOCK) ON lgc.CurrencyId = e.ExchangeId
			WHERE ld.DiscountGroupId = lgc.DiscountGroupId
		) ca
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
	IF @RebateGroupType = 32
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
		,@SPName		= 'LA_RebateDel'
		,@CustId		= @GroupId
		,@Duration		= @duration
		,@TrackingValue2 = @LogSPData
		,@TrackingValue = @LogSPDataOld
		,@ActionID		 = @actionID
END
GO
