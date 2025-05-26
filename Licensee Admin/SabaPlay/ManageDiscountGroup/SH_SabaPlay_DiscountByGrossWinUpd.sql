/*<info serverAlias="DBCUST-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
CREATE PROCEDURE [dbo].[SH_SabaPlay_DiscountByGrossWinUpd] 
	@DiscountGroupId	SMALLINT
	,@DiscountGroupName	NVARCHAR(110)
	,@BaseCurrencyId	INT
	,@FromDate			DATE
	,@ToDate			DATE
	,@ProductIds		VARCHAR(512) = ''
	,@OperatorIds		VARCHAR(MAX) = ''
	,@DiscountRate		DECIMAL(9, 8)
	,@UserId			INT
	,@LoginIp			VARCHAR(50) = ''
	,@ErrCode			INT = 0 OUTPUT
	,@ErrMsg			VARCHAR(4000)= '' OUTPUT
AS
/*
	Created: 20250516@Eddie
	DB: DBCUST.bodb_licensee
	Task: SabaPlay - Manage Discount Group for SabaPlay - Edit

	Revisions:
		- 20250516@Eddie: Initialize SP [RedmineID: #220534]

*/

BEGIN
	SET NOCOUNT ON
	DECLARE @StartRun DATETIME
		  , @Duration INT
		  , @LogSPData NVARCHAR(MAX)
		  , @LogSPDataOld NVARCHAR(MAX)
		  , @ActionID INT = 1604 -- DBLOG.bodb_CustomerLog.dbo.LA_LogAction.[ActionID]
		  , @SPName VARCHAR(50) = OBJECT_NAME(@@PROCID)

	DECLARE @Products TABLE (ProductId TINYINT)
	DECLARE @Operators TABLE (PartyId INT)

	SET @StartRun = GETDATE()
	
	INSERT INTO @Products(ProductId)
	SELECT DISTINCT value FROM STRING_SPLIT(@ProductIds, ',')
	
	INSERT INTO @Operators(PartyId)
	SELECT DISTINCT value FROM STRING_SPLIT(@OperatorIds, ',')

	-- Validate input data
	BEGIN

		IF ISNULL(@DiscountGroupName, '') = '' OR @FromDate IS NULL OR @ToDate IS NULL OR ISNULL(@BaseCurrencyId, 0) = 0
		BEGIN
			SELECT @ErrCode = 501, @ErrMsg = 'Please fill in all required field!'
			RETURN
		END

		IF @DiscountRate < 0 OR @DiscountRate > 100
		BEGIN
			SELECT @ErrCode = 512, @ErrMsg = 'Discount Rate cannot be negative or greater than 100.'
			RETURN
		END

		IF NOT EXISTS ( SELECT 1
						FROM dbo.LA_DiscountGroupHeader WITH (NOLOCK)
						WHERE DiscountGroupId = @DiscountGroupId
						  AND DiscountGroupType = 23
		)
		BEGIN
			SELECT @ErrCode = 509, @ErrMsg = 'This group does not exist. Please check again.'
			RETURN
		END

		IF EXISTS ( SELECT 1
					FROM dbo.LA_DiscountGroupHeader WITH (NOLOCK)
					WHERE DiscountGroupName = @DiscountGroupName
					  AND DiscountGroupType = 23
					  AND DiscountGroupId <> @DiscountGroupId
		)
		BEGIN
			SELECT @ErrCode = 502, @ErrMsg = 'Group Name already exists. Please try another one!'
			RETURN
		END

		IF @ProductIds = ''
		BEGIN
			SELECT @ErrCode = 503, @ErrMsg = 'Please select at least 1 product!'
			RETURN	
		END
		
		IF @OperatorIds = ''
		BEGIN
			SELECT @ErrCode = 504, @ErrMsg = 'Please select at least 1 operator!'
			RETURN	
		END

		IF EXISTS (
			SELECT 1
			FROM @Products p
				LEFT JOIN dbo.vw_SabaPlay_Products vw WITH (NOLOCK) ON vw.ProductId = p.ProductId
			WHERE vw.ProductId IS NULL
		)
		BEGIN
			SELECT @ErrCode = 505, @ErrMsg = 'Product(s) do not exist.'
			RETURN
		END

		IF EXISTS (
			SELECT 1
			FROM @Operators p
				LEFT JOIN dbo.OAS_Party op WITH (NOLOCK) ON op.PartyId = p.PartyId
			WHERE op.PartyID IS NULL OR op.PlatformId <> 2
		)
		BEGIN
			SELECT @ErrCode = 506, @ErrMsg = 'Operator(s) do not exist.'
			RETURN
		END

		IF EXISTS (
			SELECT 1
			FROM @Operators p
				LEFT JOIN dbo.OAS_PartyBaseCurrency bc WITH (NOLOCK) ON p.PartyId = bc.PartyId AND bc.FromDate <= @ToDate AND bc.ToDate >= @FromDate
			WHERE bc.PartyId IS NULL OR bc.BaseCurrencyId <> @BaseCurrencyId
		)
		BEGIN
			SELECT @ErrCode = 507, @ErrMsg = 'Operators billing currency must be the same.'
			RETURN
		END

		IF EXISTS (
			SELECT 1
			FROM dbo.LA_DiscountGroupHeader h WITH (NOLOCK)
				INNER JOIN dbo.LA_DiscountGroupAssignment a WITH (NOLOCK) ON h.DiscountGroupId = a.DiscountGroupId
				INNER JOIN dbo.LA_DiscountGroupProduct p WITH (NOLOCK) ON p.DiscountGroupId = a.DiscountGroupId
				INNER JOIN @Operators o ON o.PartyId = a.PartyId
				INNER JOIN @Products pt ON pt.ProductId = p.ProductId
			WHERE h.DiscountGroupType = 23 AND h.FromDate <= @ToDate AND h.ToDate >= @FromDate
			  AND h.DiscountGroupId <> @DiscountGroupId
		)
		BEGIN
			SELECT @ErrCode = 511, @ErrMsg = 'The selected Operator(s) already belong to another discount group with the same product(s). Please adjust your selection!'
			RETURN
		END

	END

	-- Old data
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

	-- #Region Update
	BEGIN TRY

		UPDATE dbo.LA_DiscountGroupHeader WITH (ROWLOCK, UPDLOCK)
		SET DiscountGroupName = @DiscountGroupName
		  , FromDate = @FromDate
		  , ToDate = @ToDate
		  , ModifiedDate = GETDATE()
		  , CurrencyId = @BaseCurrencyId
		WHERE DiscountGroupId = @DiscountGroupId

		UPDATE dbo.LA_DiscountGroupDetail WITH (ROWLOCK, UPDLOCK)
		SET Rate = @DiscountRate
		WHERE DiscountGroupId = @DiscountGroupId

		;MERGE dbo.LA_DiscountGroupProduct WITH( ROWLOCK, UPDLOCK) AS t
		USING @Products AS s
		ON (t.DiscountGroupId = @DiscountGroupId AND t.ProductId = s.ProductId)
		WHEN NOT MATCHED BY TARGET
			THEN INSERT(DiscountGroupId, ProductId, CalculationType)
				 VALUES(@DiscountGroupId, s.ProductId, 0)
		WHEN NOT MATCHED BY SOURCE AND t.DiscountGroupId = @DiscountGroupId
			THEN DELETE;

		;MERGE dbo.LA_DiscountGroupAssignment WITH (ROWLOCK, UPDLOCK) AS t
		USING @Operators AS s
		ON (t.DiscountGroupId = @DiscountGroupId AND t.PartyId = s.PartyId)
		WHEN NOT MATCHED BY TARGET
			THEN INSERT(DiscountGroupId, PartyId, IsApplyDiscount)
				 VALUES(@DiscountGroupId, s.PartyId, 1)
		WHEN NOT MATCHED BY SOURCE AND t.DiscountGroupId = @DiscountGroupId
			THEN DELETE;

	END TRY
	BEGIN CATCH

		SELECT @ErrCode = 510, @ErrMsg = 'Update failed. Please try again.'
		RETURN

	END CATCH

	SET @Duration = DATEDIFF(MILLISECOND, @StartRun, GETDATE())

	SELECT @logSPData = (
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

	-- Write Log
	EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
		@UserId			 = @UserId
		,@IP			 = @LoginIp
		,@SPName		 = @SPName
		,@CustId		 = @DiscountGroupId
		,@Duration		 = @Duration
		,@TrackingValue2 = @LogSPData
		,@TrackingValue  = @LogSPDataOld
		,@ActionID		 = @ActionID

END
GO