/*<info serverAlias="DBCUST-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_RebateUpd] 
	@GroupId			SMALLINT = 0,
	@GroupName			NVARCHAR(50),
	@FromDate			DATE,
	@ToDate				DATE,
	@ProductIds			VARCHAR(512) = '',
	@PartyIds			VARCHAR(MAX) = '',
	@Rate				DECIMAL(9, 8),
	@RebateGroupType	TINYINT,
	@UserId				INT,
	@Remark				NVARCHAR(4000) = '',
	@LoginIp			VARCHAR (50)	= '',
	@ErrCode			INT = 0 OUTPUT,
	@ErrMsg				VARCHAR(4000)= '' OUTPUT,
	@CurrencyIds		VARCHAR(4000) = ''
AS
/*  
	 Created: 20180528@Parsons [#94282]
	 Task : Enhance Manage Discount group function to support more discount schemes
	 DB: DBCUST.bodb_licensee   

	 Revisions:  
		- 20180528@Parsons: Update rebate group [#94282]
		- 20190510@Percy: Migrate to DBCUST.bodb_Licensee [RedmineID: #103658]
		- 20220210@Percy: Add param @RebateGroupType to offer Tier Rebate [RedmineID: #163495]
		- 20220506@Percy: Add new rebate type: Rebate on Licensee WL [RedmineID: #1732342]
		- 20220509@Danny: Use String_split built-in function [RemineID: #171831]
		- 20230417@Danny: Insert new log with more information [#FeatureID 175125]
		- 20241016@Danny: Extend parameter data length [RemineID: #212252]
		- 20240613@Danny: Rebate on specific currencies [#FeatureID 206143]

*/

BEGIN
	SET NOCOUNT ON
	DECLARE @startRun DATETIME, @endRun DATETIME, @duration INT, @logSPData NVARCHAR(MAX), 
			@logSPDataOld	NVARCHAR(MAX), @actionID INT = 1701

	SET @startRun = GETDATE()

	--check empty
	IF ISNULL(@GroupName, '') = ''
	BEGIN
		SELECT @ErrCode = 501, @ErrMsg = 'Please fill out group name.'
		RETURN
	END

	--check exists
	IF EXISTS (SELECT 1 FROM dbo.LA_DiscountGroupHeader WITH(NOLOCK) WHERE DiscountGroupName = @GroupName AND DiscountGroupType IN (2, 12, 22, 32) AND DiscountGroupId <> @GroupId)
	BEGIN
		SELECT @ErrCode = 502, @ErrMsg = 'Group name exists. Please try again.'
		RETURN
	END

	DECLARE @Products TABLE (ProductId TINYINT)
	DECLARE @Payers TABLE (PayerId INT)
	DECLARE @Currencies TABLE (CurrencyId INT)

	--parse product rebate group
	IF @ProductIds = ''
	BEGIN
		SELECT @ErrCode = 503, @ErrMsg = 'Please select at least 1 product!'
		RETURN	
	END

	IF @RebateGroupType = 32 AND @CurrencyIds = ''
	BEGIN
		SELECT @ErrCode = 503, @ErrMsg = 'Please add at least one currency.'
		RETURN	
	END

	INSERT INTO @Products(ProductId)
	SELECT value FROM STRING_SPLIT(@ProductIds, ',')

	INSERT INTO @Currencies(CurrencyId)
	SELECT value FROM STRING_SPLIT(@CurrencyIds, ',')

	--parse assigned payer to group
	IF @PartyIds = ''
	BEGIN
		SELECT @ErrCode = 503, @ErrMsg = 'Please add at least one licensee.'
		RETURN	
	END
		
	INSERT INTO @Payers(PayerId)
	SELECT value FROM STRING_SPLIT(@PartyIds, ',')
	
	--check required fields
	IF @FromDate IS NULL OR @ToDate IS NULL
		OR (NOT EXISTS (SELECT 1 FROM @Products))
		OR @Rate < 0
	BEGIN
		SELECT @ErrMsg = 'Please fill all required field.', @ErrCode = 503
		RETURN
	END

	-- check exists setting
	BEGIN
		SELECT @ErrMsg = ''
		
		IF @RebateGroupType = 12 -- Tier Rebate
		BEGIN
			IF EXISTS (
				SELECT TOP 1 1 
				FROM dbo.LA_DiscountGroupHeader h WITH (NOLOCK)
				INNER JOIN dbo.LA_DiscountGroupAssignment a WITH (NOLOCK) ON h.DiscountGroupId = a.DiscountGroupId
				INNER JOIN @Payers t ON t.PayerId = a.PartyID
				WHERE h.DiscountGroupType = 12 AND h.FromDate <= @ToDate AND h.ToDate >= @FromDate
					AND h.DiscountGroupId <> @GroupId
			)
			BEGIN
				SELECT @ErrCode = 503, @ErrMsg = 'Licensee is in another Tier Rebate group.'
				RETURN
			END	
		END

		IF @RebateGroupType IN (2, 22)
		BEGIN
			IF EXISTS (
				SELECT TOP 1 1 
				FROM dbo.LA_DiscountGroupHeader h WITH (NOLOCK)
				INNER JOIN dbo.LA_DiscountGroupAssignment a WITH (NOLOCK) ON h.DiscountGroupId = a.DiscountGroupId
				INNER JOIN dbo.LA_DiscountGroupProduct p WITH (NOLOCK) ON p.DiscountGroupId = a.DiscountGroupId
				INNER JOIN @Payers t ON t.PayerId = a.PartyID
				INNER JOIN @Products pt ON pt.ProductId = p.ProductId
				WHERE h.DiscountGroupType = 2 AND h.FromDate <= @ToDate AND h.ToDate >= @FromDate AND h.DiscountGroupId <> @GroupId
			)
			BEGIN
				SELECT @ErrCode = 503, @ErrMsg = 'Licensee is in another Rebate on Lic Fee for all currencies group.'
				RETURN
			END	

			IF EXISTS (
				SELECT TOP 1 1 
				FROM dbo.LA_DiscountGroupHeader h WITH (NOLOCK)
				INNER JOIN dbo.LA_DiscountGroupAssignment a WITH (NOLOCK) ON h.DiscountGroupId = a.DiscountGroupId
				INNER JOIN dbo.LA_DiscountGroupProduct p WITH (NOLOCK) ON p.DiscountGroupId = a.DiscountGroupId
				INNER JOIN @Payers t ON t.PayerId = a.PartyID
				INNER JOIN @Products pt ON pt.ProductId = p.ProductId
				WHERE h.DiscountGroupType = 22 AND h.FromDate <= @ToDate AND h.ToDate >= @FromDate AND h.DiscountGroupId <> @GroupId
			)
			BEGIN
				SELECT @ErrCode = 503, @ErrMsg = 'Licensee is in another Rebate on Lic WL group.'
				RETURN
			END	

			IF EXISTS (
				SELECT TOP 1 1 
				FROM dbo.LA_DiscountGroupHeader h WITH (NOLOCK)
				INNER JOIN dbo.LA_DiscountGroupAssignment a WITH (NOLOCK) ON h.DiscountGroupId = a.DiscountGroupId
				INNER JOIN dbo.LA_DiscountGroupProduct p WITH (NOLOCK) ON p.DiscountGroupId = a.DiscountGroupId
				INNER JOIN @Payers t ON t.PayerId = a.PartyID
				INNER JOIN @Products pt ON pt.ProductId = p.ProductId
				WHERE h.DiscountGroupType = 32 AND h.FromDate <= @ToDate AND h.ToDate >= @FromDate AND h.DiscountGroupId <> @GroupId
			)
			BEGIN
				SELECT @ErrCode = 503, @ErrMsg = 'Licensee is in another Rebate on Lic Fee for specific curencies group.'
				RETURN
			END	
		END

		IF @RebateGroupType = 32
		BEGIN
			IF EXISTS (
				SELECT TOP 1 1 
				FROM dbo.LA_DiscountGroupHeader h WITH (NOLOCK)
				INNER JOIN dbo.LA_DiscountGroupAssignment a WITH (NOLOCK) ON h.DiscountGroupId = a.DiscountGroupId
				INNER JOIN dbo.LA_DiscountGroupProduct p WITH (NOLOCK) ON p.DiscountGroupId = a.DiscountGroupId
				INNER JOIN @Payers t ON t.PayerId = a.PartyID
				INNER JOIN @Products pt ON pt.ProductId = p.ProductId
				WHERE h.DiscountGroupType = 2 AND h.FromDate <= @ToDate AND h.ToDate >= @FromDate AND h.DiscountGroupId <> @GroupId
			)
			BEGIN
				SELECT @ErrCode = 503, @ErrMsg = 'Licensee is in another Rebate on Lic Fee for all currencies group.'
				RETURN
			END	

			IF EXISTS (
				SELECT TOP 1 1 
				FROM dbo.LA_DiscountGroupHeader h WITH (NOLOCK)
				INNER JOIN dbo.LA_DiscountGroupAssignment a WITH (NOLOCK) ON h.DiscountGroupId = a.DiscountGroupId
				INNER JOIN dbo.LA_DiscountGroupProduct p WITH (NOLOCK) ON p.DiscountGroupId = a.DiscountGroupId
				INNER JOIN @Payers t ON t.PayerId = a.PartyID
				INNER JOIN @Products pt ON pt.ProductId = p.ProductId
				WHERE h.DiscountGroupType = 22 AND h.FromDate <= @ToDate AND h.ToDate >= @FromDate AND h.DiscountGroupId <> @GroupId
			)
			BEGIN
				SELECT @ErrCode = 503, @ErrMsg = 'Licensee is in another Rebate on Lic WL group.'
				RETURN
			END	

			IF EXISTS (
				SELECT TOP 1 1 
				FROM dbo.LA_DiscountGroupHeader h WITH (NOLOCK)
				INNER JOIN dbo.LA_DiscountGroupAssignment a WITH (NOLOCK) ON h.DiscountGroupId = a.DiscountGroupId
				INNER JOIN dbo.LA_DiscountGroupProduct p WITH (NOLOCK) ON p.DiscountGroupId = a.DiscountGroupId
				INNER JOIN dbo.LA_DiscountGroupCurrency c WITH (NOLOCK) ON c.DiscountGroupId = a.DiscountGroupId AND c.PartyID = a.PartyID
				INNER JOIN @Payers t ON t.PayerId = a.PartyID
				INNER JOIN @Products pt ON pt.ProductId = p.ProductId
				INNER JOIN @Currencies cs ON cs.CurrencyId = c.CurrencyId
				WHERE h.DiscountGroupType = 32 AND h.FromDate <= @ToDate AND h.ToDate >= @FromDate AND h.DiscountGroupId <> @GroupId
			)
			BEGIN
				SELECT @ErrCode = 503, @ErrMsg = 'Licensee is in another Rebate on Lic Fee for specific curencies group.'
				RETURN
			END	
		END
	END

	-- if group is tier rebate, check base currency all payers
	DECLARE @BaseCurrency TABLE (BaseCurrencyId INT)
	DECLARE @BaseCurrencyId INT = 0

	IF @RebateGroupType = 12
	BEGIN
		INSERT INTO @BaseCurrency (BaseCurrencyId)
		SELECT DISTINCT BaseCurrencyId
		FROM @Payers p
			INNER JOIN dbo.OAS_PartyBaseCurrency bc WITH (NOLOCK) ON p.PayerId = bc.PartyId
		WHERE bc.FromDate <= @ToDate AND bc.ToDate >= @FromDate

		IF @@ROWCOUNT <> 1
		BEGIN
			SELECT @ErrCode = 503, @ErrMsg = 'Licensees billing currency must be the same.'
			RETURN
		END

		SELECT @BaseCurrencyId = BaseCurrencyId FROM @BaseCurrency
	END

	-- #Region Update 
	IF ISNULL(@GroupId, 0) = 0
	BEGIN
		SELECT @ErrMsg = 'Update failed. Please try again.', @ErrCode = 504
		RETURN
	END

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
				CASE WHEN @RebateGroupType = 32 THEN ca.val ELSE 'All currencies' END AS 'gs.ca'
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

	--update rebate group assingment
	;MERGE dbo.LA_DiscountGroupAssignment WITH(ROWLOCK, UPDLOCK) AS t
	USING @Payers AS s
	ON (t.DiscountGroupId = @GroupId AND t.PartyId = s.PayerId)
	WHEN NOT MATCHED BY TARGET
		THEN INSERT(DiscountGroupId, PartyId, IsApplyDiscount)
				VALUES(@GroupId, s.PayerId, 0)
	WHEN NOT MATCHED BY SOURCE AND t.DiscountGroupId = @GroupId
		THEN DELETE;

	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Update failed. Please try again.', @ErrCode = 504
		RETURN
	END

	--update rebate group product
	;MERGE dbo.LA_DiscountGroupProduct WITH(ROWLOCK, UPDLOCK) AS t
	USING @Products AS s
	ON (t.DiscountGroupId = @GroupId AND t.ProductId = s.ProductId)
	WHEN NOT MATCHED BY TARGET
		THEN INSERT(DiscountGroupId, ProductId, CalculationType)
				VALUES(@GroupId, s.ProductId, 0)
	WHEN NOT MATCHED BY SOURCE AND t.DiscountGroupId = @GroupId
		THEN DELETE;

	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Update failed. Please try again.', @ErrCode = 504
		RETURN
	END

	
	; WITH s AS 
	(
		SELECT PayerId AS PartyID, CAST (x.value AS INT) CurrencyId
		FROM @Payers
		CROSS JOIN STRING_SPLIT (@CurrencyIds,',') x

	)MERGE dbo.LA_DiscountGroupCurrency WITH(ROWLOCK, UPDLOCK) AS t
	USING  s
	ON (t.DiscountGroupId = @GroupId AND t.PartyID = s.PartyID AND t.CurrencyId = s.CurrencyId)
	WHEN NOT MATCHED BY TARGET
		THEN INSERT(DiscountGroupId, PartyID, CurrencyId)
				VALUES(@GroupId, s.PartyID, s.CurrencyId)
	WHEN NOT MATCHED BY SOURCE AND t.DiscountGroupId = @GroupId
		THEN DELETE;
	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Update failed. Please try again.', @ErrCode = 504
		RETURN
	END


	--update rebate group detail
	UPDATE dbo.LA_DiscountGroupDetail WITH(ROWLOCK, UPDLOCK)
	SET Rate = @Rate
	WHERE DiscountGroupId = @GroupId

	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Update failed. Please try again.', @ErrCode = 504
		RETURN
	END

	--update rebate group header
	UPDATE dbo.LA_DiscountGroupHeader WITH(ROWLOCK, UPDLOCK)
	SET DiscountGroupName = @GroupName
		, FromDate = @FromDate
		, ToDate = @ToDate
		, Remark = @Remark
		, ModifiedDate = GETDATE()
		, DiscountGroupType = @RebateGroupType
		, CurrencyId = @BaseCurrencyId
	WHERE DiscountGroupId = @GroupId

	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Update failed. Please try again.', @ErrCode = 504
		RETURN
	END

	-- #Endregion Update 

	--write log
	SET @endRun = GETDATE()
	SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun)
	SELECT @logSPData = (
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
				CASE WHEN @RebateGroupType = 32 THEN ca.val ELSE 'All currencies' END AS 'gs.ca'
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

	-- Write Log
	EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
		@UserId			= @UserID
		,@IP			= @LoginIp
		,@SPName		= 'LA_RebateUpd'
		,@CustId		= @GroupId
		,@Duration		= @duration
		,@TrackingValue2 = @LogSPData
		,@TrackingValue = @LogSPDataOld
		,@ActionID		 = @actionID
END
GO
