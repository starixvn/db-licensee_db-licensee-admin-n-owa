/*<info serverAlias="DBCUST-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_ChargeRateGroupChange]
	@GroupId		INT,
	@PartyId		INT,
	@EffectiveDate	DATE,
	@UserId			INT = 0,
	@ErrCode		INT				= 0		OUTPUT,
	@ErrMsg			NVARCHAR(1000)	= ''	OUTPUT
AS
/*
	Created: 20190221@Parsons
	Task: Get Payer setting
	DB: DBCUST.bodb_Licensee

	Revisions:
		- 20190221@Parsons: Manage Payer Setting - changing party group [#109189]
		- 20190510@Percy: Migrate to DBCUST.bodb_Licensee [RedmineID: #103658]

	Params:
	Example:
*/
BEGIN
	SET NOCOUNT ON

	DECLARE		@StartRun		DATETIME,
				@EndRun			DATETIME,
				@Duration		INT,
				@LogSPData		VARCHAR(5000),
				@LogSPDataOld	VARCHAR(5000),
				@Doing			NVARCHAR(MAX)
	SET @StartRun = GETDATE()

	DECLARE @IsActived INT = 1, @IsActivating INT = 2, @IsExpired INT = 3
	DECLARE @ProductListAll	VARCHAR(100) = '', @MinDate DATE, @MaxDate	DATE	
	
	SELECT @ProductListAll = @ProductListAll + ProductPrefix + ','
	FROM dbo.LA_f_Products3rd('')
	WHERE ProductPrefix <> 'RB' -- dont support RB

	SELECT @MinDate = MIN(ci.FromDate), @MaxDate = MAX(ci.ToDate)
	FROM dbo.OAS_ChargeInfo ci WITH (NOLOCK)
	INNER JOIN dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK) ON ci.ChargeID = cs.ChargeID AND cs.SystemID = 2
	WHERE ci.FromParty = @PartyId

	SELECT DISTINCT c1.ChargeID, c1.ProductID, FromParty, ToParty, ParentChargeID, Rate, c1.ChargeType, c1.FromDate, c1.ToDate, Remark, BaseCurrencyId, FirstOfBilling, BasisOfBilling,
			CASE
				WHEN c1.FromDate < @EffectiveDate AND c1.ToDate >= @EffectiveDate THEN @IsActived
				WHEN c1.FromDate >= @EffectiveDate THEN @IsActivating
				ELSE @IsExpired
			END AS [Status]
	INTO #ChangeRateTable
	FROM OAS_ChargeInfo c1 WITH(NOLOCK)
	INNER JOIN dbo.LA_f_ChargeInfo(@PartyId, @MinDate, @MaxDate, @ProductListAll, 'OA', 1) c2 ON c1.ChargeID = c2.ChargeID

	--Step1: Expire all active charge rates at EffectiveDate - 1
		-- 1.1 Update OAS_ChargeInfo
	UPDATE c1
	SET ToDate = DATEADD(DAY, -1, @EffectiveDate)
	FROM OAS_ChargeInfo c1 WITH(NOLOCK) 
	INNER JOIN #ChangeRateTable c2 ON c1.ChargeID = c2.ChargeID
	WHERE [Status] = @IsActived

		-- 1.2 Update OAS_ChargeInfoSub
	UPDATE cs
	SET ToDate = DATEADD(DAY, -1, @EffectiveDate)
	FROM OAS_ChargeInfoSub cs WITH(NOLOCK) 
	INNER JOIN #ChangeRateTable c ON cs.ChargeIdRef = c.ChargeID 
	WHERE [Status] = @IsActived

	IF @@Error > 0
	BEGIN
		UPDATE c1
		SET c1.ToDate = c2.ToDate
		FROM OAS_ChargeInfo c1 WITH(NOLOCK) 
		INNER JOIN #ChangeRateTable c2 ON c1.ChargeID = c2.ChargeID
		WHERE [Status] = @IsActived

		UPDATE cs
		SET ToDate = c.ToDate
		FROM OAS_ChargeInfoSub cs WITH(NOLOCK) 
		INNER JOIN #ChangeRateTable c ON cs.ChargeIdRef = c.ChargeID
		WHERE [Status] = @IsActived 

		SELECT @ErrMsg = 'Fail to expire all active charge rates: ' + ERROR_MESSAGE(), @ErrCode = 504
		RETURN
	END

	--Step2: Copy charge rates to new group with FromDate = Effective date
	DECLARE @InsertedResult TABLE (ChargeId INT, ProductId INT)

		-- 2.1 OAS_ChargeInfo
	INSERT INTO OAS_ChargeInfo(ProductID, FromParty, ToParty, ParentChargeID, Rate, ChargeType, FromDate, ToDate, Remark, BaseCurrencyId, FirstOfBilling, BasisOfBilling)
	OUTPUT INSERTED.ChargeID, INSERTED.ProductId INTO @InsertedResult(ChargeId, ProductId)
	SELECT ProductID, FromParty, @GroupId, ParentChargeID, Rate, ChargeType, @EffectiveDate, ToDate, Remark, BaseCurrencyId, FirstOfBilling, BasisOfBilling
	FROM #ChangeRateTable
	WHERE [Status] = @IsActived

		-- 2.2 LA_ChargeInfo_SystemMapping
	INSERT INTO LA_ChargeInfo_SystemMapping(ChargeID, SystemID)
	SELECT ChargeID, 2
	FROM @InsertedResult

		-- 2.3 OAS_ChargeInfoSub
	INSERT INTO OAS_ChargeInfoSub (ProductID, BettypeRef, FromParty, ToParty, ParentChargeID, Rate, ChargeType, FromDate, ToDate, BaseCurrencyId, FirstOfBilling, BasisOfBilling, ChargeIdRef)
	SELECT cs.ProductID, cs.BettypeRef, cs.FromParty, @GroupId , cs.ParentChargeID, cs.Rate, cs.ChargeType, @EffectiveDate, c.ToDate, cs.BaseCurrencyId, cs.FirstOfBilling, cs.BasisOfBilling, ins.ChargeId 
	FROM [dbo].[OAS_ChargeInfoSub] cs WITH(NOLOCK)
	INNER JOIN #ChangeRateTable c ON cs.ChargeIdRef = c.ChargeID
	INNER JOIN @InsertedResult ins ON cs.ProductID = ins.ProductId
	WHERE [Status] = @IsActived

	IF @@Error > 0
	BEGIN
		UPDATE c1
		SET c1.ToDate = c2.ToDate
		FROM OAS_ChargeInfo c1 WITH(NOLOCK) 
		INNER JOIN #ChangeRateTable c2 ON c1.ChargeID = c2.ChargeID
		WHERE [Status] = @IsActived

		DELETE c
		FROM OAS_ChargeInfo c 
		INNER JOIN @InsertedResult ins ON c.ChargeID = ins.ChargeID

		UPDATE cs
		SET ToDate = c.ToDate
		FROM OAS_ChargeInfoSub cs WITH(NOLOCK) 
		INNER JOIN #ChangeRateTable c ON cs.ChargeIdRef = c.ChargeID 
		WHERE [Status] = @IsActived

		DELETE cs
		FROM OAS_ChargeInfoSub cs 
		INNER JOIN @InsertedResult ins ON cs.ChargeIdRef = ins.ChargeID

		SELECT @ErrMsg = 'Fail to copy charge rates to new group: ' + ERROR_MESSAGE(), @ErrCode = 505
		RETURN
	END

	/*Step3: Special case, 
		ex: FromDate: 5
			ToDate: 10
			EffectiveDate: 5
		=> Need only to update group
	*/
		-- 3.1 OAS_ChargeInfo
	UPDATE c1
	SET ToParty = @GroupId
	FROM OAS_ChargeInfo c1 WITH(NOLOCK) 
	INNER JOIN #ChangeRateTable c2 ON c1.ChargeID = c2.ChargeID
	WHERE [Status] = @IsActivating
		-- 3.2 OAS_ChargeInfoSub
	UPDATE cs
	SET ToParty = @GroupId
	FROM OAS_ChargeInfoSub cs WITH(NOLOCK) 
	INNER JOIN #ChangeRateTable c ON cs.ChargeIdRef = c.ChargeID
	WHERE [Status] = @IsActivating

	SET @EndRun = GETDATE()
	SET @Duration = DATEDIFF (MILLISECOND, @StartRun, @EndRun)

	SET @Doing =(SELECT	@GroupId		AS GroupId,
						@PartyId		AS PartyId,
						@EffectiveDate	AS [EffectiveDate],
						@UserId			AS	UserId,
						(SELECT ChargeID, ProductID, FromParty, ToParty, ParentChargeID, Rate, ChargeType, FromDate, ToDate, Remark, BaseCurrencyId, FirstOfBilling, BasisOfBilling, [Status]
							FROM #ChangeRateTable
							FOR XML PATH('ChangeRateTable'), TYPE) AS ChangeRateTables
						FOR XML PATH('')) 
	
	EXEC CustDB.dbo.WriteLog_UserLog_UserControl_Wrapper
		@CustID		= 0
		,@Doing		= @Doing
		,@UserID	= @UserId
		,@TypeID	= 0
		,@ActionID	= 5546
		,@Duration	= @Duration

	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Fail to write log: ' + ERROR_MESSAGE() , @ErrCode = 506
	END

	DROP TABLE #ChangeRateTable
END
GO