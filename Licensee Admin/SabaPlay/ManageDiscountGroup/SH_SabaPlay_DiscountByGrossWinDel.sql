/*<info serverAlias="DBCUST-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
CREATE PROCEDURE [dbo].[SH_SabaPlay_DiscountByGrossWinDel]
	@DiscountGroupId SMALLINT
	,@UserId 		 INT
	,@LoginIp 		 VARCHAR(50) = ''
	,@ErrCode 		 INT = 0 OUTPUT
	,@ErrMsg 		 VARCHAR(4000) = '' OUTPUT
AS
/*
	Created: 20250516@Eddie
	DB: DBCUST.bodb_licensee
	Task: SabaPlay - Manage Discount Group for SabaPlay - Delete 

	Revisions:
		- 20250516@Eddie: Initialize SP [RedmineID: #220534]

*/
BEGIN
	SET NOCOUNT ON
	DECLARE @StartRun DATETIME
		  , @Duration INT
		  , @LogSPData NVARCHAR(MAX)
		  , @LogSPDataOld NVARCHAR(MAX)
		  , @ActionID INT = 1605 -- DBLOG.bodb_CustomerLog.dbo.LA_LogAction.[ActionID]
		  , @SPName VARCHAR(50) = OBJECT_NAME(@@PROCID)

	SET @StartRun = GETDATE()

	-- Data for log
	SELECT @logSPDataOld = (
		SELECT ld.DiscountGroupName AS 'gs.gn'
			  ,CAST (ldg.Rate * 100 AS VARCHAR(50)) + ' %' AS 'gs.dr'
			  ,e.Code  AS 'gs.e'
			  ,FORMAT (ld.FromDate,'MMM dd, yyyy') AS 'gs.af'
			  ,FORMAT (ld.ToDate,'MMM dd, yyyy')   AS 'gs.at'
			  ,pa.val  AS 'gs.pa'
			  ,pig.val AS 'gs.oig'
		FROM dbo.LA_DiscountGroupHeader ld WITH (NOLOCK)
			INNER JOIN dbo.LA_DiscountGroupDetail ldg WITH (NOLOCK) ON ld.DiscountGroupId = ldg.DiscountGroupId
			INNER JOIN Custdb.dbo.Exchange e WITH (NOLOCK) ON ld.CurrencyId = e.ExchangeId
			CROSS APPLY (
					SELECT STRING_AGG(op.PartyName, ', ') AS val
					FROM dbo.LA_DiscountGroupAssignment lda WITH (NOLOCK)
						INNER JOIN dbo.OAS_Party op WITH (NOLOCK) ON lda.PartyID = op.PartyID
					WHERE lda.DiscountGroupId = ld.DiscountGroupId
			) pig
			CROSS APPLY 
			(
				SELECT STRING_AGG(vw.ProductName, ', ') AS val
				FROM dbo.LA_DiscountGroupProduct ldp WITH (NOLOCK)
					LEFT JOIN dbo.vw_SabaPlay_Products vw WITH (NOLOCK) ON vw.ProductId = ldp.ProductId
				WHERE ld.DiscountGroupId = ldp.DiscountGroupId
			) pa
		WHERE ld.DiscountGroupId = @DiscountGroupId
		FOR JSON PATH, WITHOUT_ARRAY_WRAPPER 
	)

	--Validate this discount has applied to Invoice yet
	DECLARE @HasBilling BIT = 0
	EXEC dbo.SH_SabaPlay_DiscountByGrossWin_HasBilling @DiscountGroupId = @DiscountGroupId, @HasBilling = @HasBilling OUTPUT

	IF (ISNULL(@HasBilling, 0) = 1)
	BEGIN
		SELECT @ErrCode = 520, @ErrMsg = 'Cannot delete the discount group, it is being applied!'
		RETURN
	END

	BEGIN TRY

		DELETE dbo.LA_DiscountGroupAssignment WITH (ROWLOCK) WHERE DiscountGroupId = @DiscountGroupId
		DELETE dbo.LA_DiscountGroupProduct WITH (ROWLOCK) WHERE DiscountGroupId = @DiscountGroupId
		DELETE dbo.LA_DiscountGroupDetail WITH (ROWLOCK) WHERE DiscountGroupId = @DiscountGroupId
		DELETE dbo.LA_DiscountGroupHeader WITH (ROWLOCK) WHERE DiscountGroupId = @DiscountGroupId

	END TRY
	BEGIN CATCH

		SELECT @ErrCode = 521, @ErrMsg = 'Delete failed. Please try again.'
		RETURN

	END CATCH

	SET @Duration = DATEDIFF(MILLISECOND, @StartRun, GETDATE())

	-- Write Log
	EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
		@UserId			 = @UserId
		,@IP			 = @LoginIp
		,@SPName		 = @SPName
		,@CustId		 = @DiscountGroupId
		,@Duration		 = @duration
		,@TrackingValue2 = @LogSPData
		,@TrackingValue  = @LogSPDataOld
		,@ActionID		 = @ActionID
END
GO