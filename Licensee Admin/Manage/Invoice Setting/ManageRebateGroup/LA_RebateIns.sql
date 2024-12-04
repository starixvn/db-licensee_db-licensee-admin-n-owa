/*<info serverAlias="DBCUST-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_RebateIns] 
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
	@GroupIdOut			INT = 0 OUTPUT,
	@CurrencyIds		VARCHAR(4000) = ''
AS
/*  
	 Created: 20180528@Parsons [#94282]
	 Task : Enhance Manage Discount group function to support more discount schemes
	 DB: DBCUST.bodb_licensee   

	 Revisions:  
		- 20180528@Parsons: Create rebate group [#94282]
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
			@logSPDataOld	NVARCHAR(MAX), @actionID INT = 1700

	SET @startRun = GETDATE()

	--check empty
	IF ISNULL(@GroupName, '') = ''
	BEGIN
		SELECT @ErrCode = 501, @ErrMsg = 'Please fill out group name.'
		RETURN
	END

	--check exists
	IF EXISTS (SELECT 1 FROM dbo.LA_DiscountGroupHeader WITH(NOLOCK) WHERE DiscountGroupName = @GroupName AND DiscountGroupType IN (2, 12, 22, 32))
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

	INSERT INTO @Products(ProductId)
	SELECT value FROM STRING_SPLIT(@ProductIds, ',')

	--parse assigned payer to group
	IF @PartyIds = ''
	BEGIN
		SELECT @ErrCode = 503, @ErrMsg = 'Please add at least one licensee.'
		RETURN	
	END

	IF @RebateGroupType = 32 AND @CurrencyIds = ''
	BEGIN
		SELECT @ErrCode = 503, @ErrMsg = 'Please add at least one currency.'
		RETURN	
	END

	INSERT INTO @Payers(PayerId)
	SELECT value FROM STRING_SPLIT(@PartyIds, ',')

	INSERT INTO @Currencies(CurrencyId)
	SELECT value FROM STRING_SPLIT(@CurrencyIds, ',')
	
	--check required fields
	IF @FromDate IS NULL OR @ToDate IS NULL
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
				WHERE h.DiscountGroupType = 2 AND h.FromDate <= @ToDate AND h.ToDate >= @FromDate
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
				WHERE h.DiscountGroupType = 22 AND h.FromDate <= @ToDate AND h.ToDate >= @FromDate
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
				WHERE h.DiscountGroupType = 32 AND h.FromDate <= @ToDate AND h.ToDate >= @FromDate
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
				WHERE h.DiscountGroupType = 2 AND h.FromDate <= @ToDate AND h.ToDate >= @FromDate
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
				WHERE h.DiscountGroupType = 22 AND h.FromDate <= @ToDate AND h.ToDate >= @FromDate
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
				WHERE h.DiscountGroupType = 32 AND h.FromDate <= @ToDate AND h.ToDate >= @FromDate
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

	-- #Region Insert 

	--insert rebate group header
	INSERT INTO dbo.LA_DiscountGroupHeader(DiscountGroupName, DiscountGroupType, CurrencyId, FromDate, ToDate, Remark, [Priority], ModifiedDate)
	VALUES(@GroupName, @RebateGroupType, @BaseCurrencyId, @FromDate, @ToDate, @Remark, 2, GETDATE())

	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Insert failed. Please try again.', @ErrCode = 503
		RETURN
	END

	SET @GroupIdOut = SCOPE_IDENTITY()
	IF ISNULL(@GroupIdOut, 0) = 0
	BEGIN
		SELECT @ErrMsg = 'Insert failed. Please try again.', @ErrCode = 503
		RETURN
	END

	--insert rebate group detail
	INSERT INTO dbo.LA_DiscountGroupDetail(DiscountGroupId, FromAmount, ToAmount, Rate)
	Values(@GroupIdOut, 0, 0, @Rate)

	IF @@ERROR <> 0
	BEGIN
		DELETE dbo.LA_DiscountGroupHeader WITH(ROWLOCK) WHERE DiscountGroupId = @GroupIdOut
		SELECT @ErrMsg = 'Insert failed. Please try again.', @ErrCode = 503
		RETURN
	END

	--insert rebate group product
	INSERT INTO dbo.LA_DiscountGroupProduct(DiscountGroupId, ProductId, CalculationType)
	SELECT DISTINCT @GroupIdOut, ProductId, 0
	FROM @Products

	IF @@ERROR <> 0
	BEGIN
		DELETE dbo.LA_DiscountGroupHeader WITH(ROWLOCK) WHERE DiscountGroupId = @GroupIdOut
		DELETE dbo.LA_DiscountGroupDetail WITH(ROWLOCK) WHERE DiscountGroupId = @GroupIdOut
		SELECT @ErrMsg = 'Insert failed. Please try again.', @ErrCode = 503
		RETURN
	END

	--insert rebate group assignment
	INSERT INTO dbo.LA_DiscountGroupAssignment(DiscountGroupId, PartyID, IsApplyDiscount)
	SELECT DISTINCT @GroupIdOut, PayerId, 0
	FROM @Payers

	IF @@ERROR <> 0
	BEGIN
		DELETE dbo.LA_DiscountGroupHeader WITH(ROWLOCK) WHERE DiscountGroupId = @GroupIdOut
		DELETE dbo.LA_DiscountGroupDetail WITH(ROWLOCK) WHERE DiscountGroupId = @GroupIdOut
		DELETE dbo.LA_DiscountGroupProduct WITH(ROWLOCK) WHERE DiscountGroupId = @GroupIdOut
		SELECT @ErrMsg = 'Insert failed. Please try again.', @ErrCode = 503
		RETURN
	END

	IF @RebateGroupType = 32
	BEGIN
		INSERT INTO dbo.LA_DiscountGroupCurrency (DiscountGroupId, PartyID, CurrencyId)
		SELECT @GroupIdOut, PayerId, CAST (x.value AS INT) CurrencyId
		FROM @Payers
		CROSS JOIN STRING_SPLIT (@CurrencyIds,',') x

		IF @@ERROR <> 0
		BEGIN
			DELETE dbo.LA_DiscountGroupHeader WITH(ROWLOCK) WHERE DiscountGroupId = @GroupIdOut
			DELETE dbo.LA_DiscountGroupDetail WITH(ROWLOCK) WHERE DiscountGroupId = @GroupIdOut
			DELETE dbo.LA_DiscountGroupProduct WITH(ROWLOCK) WHERE DiscountGroupId = @GroupIdOut
			DELETE dbo.LA_DiscountGroupAssignment WITH(ROWLOCK) WHERE DiscountGroupId = @GroupIdOut
			SELECT @ErrMsg = 'Insert failed. Please try again.', @ErrCode = 503
			RETURN
		END
	END

	-- #Endregion Insert 

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
			WHERE lda.DiscountGroupId = ld.DiscountGroupId
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
		WHERE ld.DiscountGroupId = @GroupIdOut
		FOR JSON PATH, WITHOUT_ARRAY_WRAPPER 
	)

	-- Write Log
	EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
		@UserId			= @UserID
		,@IP			= @LoginIp
		,@SPName		= 'LA_RebateIns'
		,@CustId		= @GroupIdOut
		,@Duration		= @duration
		,@TrackingValue2 = @LogSPData
		,@TrackingValue = @LogSPDataOld
		,@ActionID		 = @actionID
END
GO
