/*<info serverAlias="DBCUST-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_PayerSettingSel]
	@PayerId		INT = 0
	,@GroupMinFee	INT = 0
	,@DiscountGroup	INT = 0
	,@RebateGroup	INT = 0
AS
/*
	Created: 20150420@Florent
	Task : Get Payer setting
	DB: DBCUST.bodb_Licensee

	Revisions:
		- 20150703@Florent: store BaseCurrencyId from OAS_ChargeInfo to OAS_PartyDetail
		- 20161025@Scofield: exclude Colossus Bet from ChargeInfo
		- 20161031@bruce.bui: include CB, charge type
		- 20170208@bruce.bui: include terminated licensees
		- 20170214@bruce.bui: show sub charge type
		- 20170215@bruce.bui: sort product
		- 20170315@Scofield: hard code for Bettrade BA [#70050]
		- 20180309@Bruce: Param @ListParty should increase length in SP LA_PayerSettingSel [#91814]
		- 20180716@bruce: add new group TEST for credit [#98126]
		- 20180503@Parsons: fix: setting won't show when set start date from future[#94108]
		- 20181114@Parsons: Configure discount settings by currency [#99694]
		- 20181214@Parsons: Integrate Bidme games  [#103695]
		- 20200206@Mason: Set billing term by currency  [#120005]
		- 20200824@Happy: Updae from PayerGroup to GroupMinFee [#138249]
		- 20210315@Parsons: Change BaseCurrency Of Licensee [#FeatureID 151466]

	Params:
	+ @PayerId : 0 get all Party
		<> 0 specify Party
	+ @@GroupMinFee : 0 get all GroupMinFee
		<> 0 specify Party
	+ @@DiscountGroup : 0 get all Party
		<> 0 specify Party
	+ @@RebateGroup : 0 get all Party
		<> 0 specify Party
	Example:
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @Rebate INT = 2
	DECLARE @DiscountIndividualFee INT = 1
	DECLARE @DiscountIndividualGrosswin INT = 3
	DECLARE @DiscountByGroupFee INT = 11
	DECLARE @DiscountByGroupGrosswin INT = 13

	DECLARE @ProductListAll VARCHAR(500) = '',
			@ListParty VARCHAR(8000) = '',
			@MinDate DATE,
			@MaxDate DATE,
			@CurrentDate DATE
	SET @CurrentDate = CONVERT(DATE, GETDATE())
	DECLARE @ChargeInfo AS TABLE(ChargeId INT, PartyId INT, PartyName VARCHAR(100), ProductId INT, ProductName VARCHAR(100),
			BettypeRef INT,Rate MONEY, FromDate DATE, ToDate DATE, FirstBilling DATE, ExchangeID INT, ExchangeName VARCHAR(50), ChargeType TINYINT)
	CREATE TABLE #Temp_ChargeInfo(ChargeId INT, PartyID INT, ProductID INT, BettypeRef INT,Rate MONEY, Fromdate DATE, Todate DATE, ChargeType TINYINT)

	DECLARE @Minfee AS TABLE(PartyId INT, ProductId INT, FeeTypeId TINYINT, FeeAmount MONEY, FromDate DATE, ToDate DATE)
	DECLARE @Discount AS TABLE(PartyId INT, ProductId INT, FromDate DATE, ToDate DATE, DiscountGroupId INT, FromAmount MONEY, ToAmount MONEY, Rate MONEY, DiscountGroupName VARCHAR(100), DiscountGroupType TINYINT)
	DECLARE @ChargeDetail AS TABLE(ChargeID INT, PartyID INT, ProductID INT, BettypeRef INT,DI_Rate MONEY, Fromdate DATE, Todate DATE, ChargeType TINYINT)

	--Get list licensee,
	SELECT	@ListParty = @ListParty + CAST(p.PartyID AS VARCHAR) + ','
	FROM	dbo.OAS_Party p WITH (NOLOCK)
			INNER JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK)
				ON p.PartyID = pd.PartyID
			LEFT JOIN dbo.LA_GroupMinFeeAssignment mfa WITH (NOLOCK)
				ON p.PartyID = mfa.PartyId
	WHERE	PartyType = 1
			AND pd.IsDeposit = 1
			AND (@PayerId = 0
			OR p.PartyID = @PayerId)
			AND (@GroupMinFee = 0
			OR mfa.GroupMinFeeID = @GroupMinFee)

	SET @ListParty = SUBSTRING(@ListParty, 0, LEN(@ListParty))
	--get list Product
	SELECT	@ProductListAll = @ProductListAll + ProductPrefix + ','
	FROM	dbo.LA_f_Products3rd('')
	SET @ProductListAll = REPLACE(SUBSTRING(@ProductListAll, 0, LEN(@ProductListAll)), 'RB', '')

	--get Minium date, maximum date
	SELECT	@MinDate = MIN(ci.FromDate),
			@MaxDate = MAX(ci.ToDate)
	FROM	dbo.OAS_ChargeInfo ci WITH (NOLOCK)
	INNER	JOIN dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK)
				ON ci.ChargeID = cs.ChargeID
				AND cs.SystemID = 2

	DECLARE @BaseCurrencyId INT, @BaseCurrencyName NVARCHAR(50)
	SELECT TOP 1 @BaseCurrencyId = p.BaseCurrencyId, @BaseCurrencyName = e.Code
	FROM OAS_PartyBaseCurrency p WITH(NOLOCK)
	LEFT JOIN CustDB.dbo.Exchange e WITH (NOLOCK) ON p.BaseCurrencyId = e.exchangeid
	WHERE PartyID = @PayerId 
	ORDER BY ToDate DESC

	INSERT INTO @ChargeDetail (ChargeID, PartyID, ProductID, BettypeRef, DI_Rate, Fromdate, Todate, ChargeType)
		SELECT
			ChargeID,
			PartyID,
			ProductID,
			CASE WHEN ProductID IN (14,17) THEN
					Bettype
				 ELSE 0 END
			AS BettypeRef,
			DI_Rate,
			Fromdate,
			Todate, 
			ChargeType
		FROM dbo.LA_f_ChargeInfo(@ListParty, @MinDate, @MaxDate, @ProductListAll, 'OA', 1)

	INSERT INTO #Temp_ChargeInfo (ChargeID, PartyID, ProductID, BettypeRef, Rate, Fromdate, Todate, ChargeType)
		SELECT 
			b.ChargeID,
			a.PartyID,
			a.ProductID,
			b.BettypeRef,
			b.DI_Rate,
			a.Fromdate,
			a.Todate, 
			a.ChargeType
		FROM (	SELECT 
						c.PartyID,
						c.ProductID,
						c.ChargeType,
						MAX(c.Fromdate) AS Fromdate,
						MAX(c.Todate) AS Todate
				FROM	@ChargeDetail c
				WHERE	@CurrentDate <= c.Todate
				GROUP BY	c.PartyID,
							c.ProductID, 
							c.ChargeType) a
		INNER JOIN @ChargeDetail b
			ON a.PartyID = b.PartyID
			AND a.ProductID = b.ProductID
			AND a.Fromdate = b.Fromdate
			AND a.Todate = b.Todate

	INSERT INTO @ChargeInfo (ChargeId, PartyId, PartyName, ProductId, ProductName, BettypeRef, Rate, FromDate, ToDate, FirstBilling, ExchangeID, ExchangeName, ChargeType)
		SELECT 
			c.ChargeID,
			c.PartyID,
			CASE
				WHEN ISNULL(pd.BrandName, '') != '' THEN pd.BrandName
				ELSE p.PartyName
			END AS PartyName,
			c.ProductID,
			pr.ProductName,
			c.BettypeRef,
			c.Rate,
			c.Fromdate,
			c.Todate,
			CASE WHEN c.ProductID IN (14,17) THEN s.FirstOfBilling ELSE ci.FirstOfBilling END,
			ISNULL(@BaseCurrencyId, 6),
			ISNULL(@BaseCurrencyName, '') AS ExchangeName,
			CASE WHEN c.ProductID IN (14,17) THEN s.ChargeType ELSE ci.ChargeType END
		FROM #Temp_ChargeInfo c
			INNER JOIN OAS_Party p WITH (NOLOCK) ON c.PartyID = p.PartyID
			INNER JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyID = pd.PartyID
			INNER JOIN dbo.LA_f_Products3rd('') pr ON c.ProductID = pr.ProductID
			INNER JOIN dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON c.ChargeID = ci.ChargeID
			LEFT JOIN dbo.OAS_ChargeInfoSub s WITH(NOLOCK) ON ci.ChargeID = s.ChargeIdRef
		WHERE @CurrentDate <= c.Todate

	-- Hard code for Bettrade BA
	INSERT INTO @ChargeInfo (ChargeId, PartyId, PartyName, ProductId, ProductName, BettypeRef, Rate, FromDate, ToDate, FirstBilling, ExchangeID, ExchangeName, ChargeType)
	SELECT ChargeId, PartyId, PartyName, ProductId, ProductName, BettypeRef, 0, FromDate, ToDate, FirstBilling, ExchangeID, ExchangeName, 13
	FROM @ChargeInfo
	WHERE ProductId = 13

	INSERT INTO @Minfee (PartyId, ProductId, FeeTypeId, FeeAmount, FromDate, ToDate)
		SELECT
			PartyId,
			ProductId,
			FeeTypeId,
			FeeAmount,
			FromDate,
			ToDate
		FROM dbo.LA_MinFee WITH (NOLOCK)
		WHERE EXISTS (SELECT
				val
			FROM dbo.strSplit(@ListParty, ',')
			WHERE PartyID = val)
				AND @CurrentDate BETWEEN FromDate AND ToDate

	INSERT INTO @Discount (PartyId, ProductId, FromDate, ToDate, FromAmount, ToAmount, Rate, DiscountGroupId, DiscountGroupName, DiscountGroupType)
		SELECT
			a.PartyID,
			p.ProductId,
			h.FromDate,
			h.ToDate,
			d.FromAmount,
			d.ToAmount,
			d.Rate,
			d.DiscountGroupId,
			h.DiscountGroupName,
			h.DiscountGroupType
		FROM dbo.LA_DiscountGroupAssignment a WITH (NOLOCK)
			INNER JOIN dbo.LA_DiscountGroupDetail d WITH (NOLOCK)
				ON a.DiscountGroupId = d.DiscountGroupId
			INNER JOIN dbo.LA_DiscountGroupHeader h WITH (NOLOCK)
				ON d.DiscountGroupId = h.DiscountGroupId
			INNER JOIN dbo.LA_DiscountGroupProduct p WITH (NOLOCK)
				ON a.DiscountGroupId = p.DiscountGroupId
		WHERE EXISTS (	SELECT val
						FROM dbo.strSplit(@ListParty, ',')
						WHERE a.PartyID = val)
			AND @CurrentDate BETWEEN h.FromDate AND h.ToDate
		GROUP BY	a.PartyID,
					p.ProductId,
					h.FromDate,
					h.ToDate,
					d.DiscountGroupId,
					h.DiscountGroupName,
					h.DiscountGroupType,
					d.FromAmount,
					d.ToAmount,
					d.Rate

	-- get terminated
	INSERT INTO @ChargeInfo (ChargeId, PartyId, PartyName, ProductId, ProductName, BettypeRef, Rate, FromDate, ToDate, FirstBilling, ExchangeID, ExchangeName, ChargeType)
	SELECT DISTINCT -1,
		d.PartyID,
		CASE
			WHEN ISNULL(pd.BrandName, '') != '' THEN pd.BrandName
			ELSE p.PartyName
		END AS PartyName,
		0,
		'Terminated',
		0,
		0,
		@MinDate,
		@MinDate,
		NULL,
		0,
		'',
		1
	FROM @ChargeDetail d
		INNER JOIN OAS_Party p WITH (NOLOCK) ON d.PartyID = p.PartyID
		INNER JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyID = pd.PartyID
	WHERE d.PartyID NOT IN (SELECT c.PartyId FROM @ChargeInfo c)

	-- product order
	DECLARE @ProductOrder TABLE(ProductId INT, OrderNumber SMALLMONEY)
	INSERT INTO @ProductOrder
	SELECT ProductId, CASE ProductId 
			WHEN 15/*CB*/ THEN 13.5 -- , make CB after BT and before MGCLC
			ELSE ProductId -- keep as it is
		END
	FROM dbo.LA_f_Products3rd('')

	--result
	;WITH cte_GroupMinFeeData AS (
		SELECT TOP(1) WITH TIES a.PartyID, h.[Name] AS GroupMinFeeName
		FROM dbo.LA_GroupMinFeeHeader h WITH(NOLOCK)
		INNER JOIN LA_GroupMinFeeAssignment a ON a.GroupMinFeeID = h.GroupMinFeeID
		WHERE (@GroupMinFee = 0 OR h.GroupMinFeeID = @GroupMinFee) AND h.ToDate >= @CurrentDate
		ORDER BY ROW_NUMBER() OVER(PARTITION BY a.PartyID ORDER BY h.ToDate DESC)
    ),Result AS (
		SELECT DISTINCT
			c.ChargeId		AS ChargeID,
			c.PartyId		AS PayerID,
			PartyName		AS PayerName,
			gmf.GroupMinFeeName		AS GroupMinFeeName,
			c.ProductId		AS ProductId,
			ProductName		AS ProductName,
			FirstBilling	AS FirstBilling,
			ISNULL(m.FeeAmount, 0) AS MinFee,
			w.FromDate		AS WaiveFrom,
			w.ToDate		AS WaiveTo,
			d.DiscountGroupName AS DiscountGroupName,
			STUFF((SELECT
					';' + ' Amount From: ' + CONVERT(VARCHAR(100), ii.FromAmount) + ' - '
					+ 'Amount To: ' + CASE
						WHEN ii.ToAmount = 10000000000000 THEN 'Unlimited'
						ELSE CONVERT(VARCHAR(100), ii.ToAmount)
					END + ' - '
					+ 'Rate: ' + CONVERT(VARCHAR(10), ii.Rate * 100) + '%'
				FROM @Discount ii
				WHERE d.DiscountGroupId = ii.DiscountGroupId
					AND d.ProductId = ii.ProductId
					AND d.PartyId = ii.PartyId
					FOR XML PATH ('')), 1, 2, '') AS DiscountGroupValues,
				r.DiscountGroupName AS RebateGroupName,
			STUFF((SELECT
					';' + ' Rate: ' + CONVERT(VARCHAR(10), ii.Rate * 100) + '%'
				FROM @Discount ii
				WHERE r.DiscountGroupId = ii.DiscountGroupId
				AND r.ProductId = ii.ProductId
				AND r.PartyId = ii.PartyId
				GROUP BY	ii.DiscountGroupId,
							ii.Rate
				FOR XML PATH ('')), 1, 2, '') AS RebateGroupValues,
			c.BettypeRef,
			c.Rate AS Rate,
			c.ExchangeID AS ExchangeID,
			c.ExchangeName AS ExchangeName,
			c.ChargeType
		FROM @ChargeInfo c
			LEFT JOIN cte_GroupMinFeeData gmf ON c.PartyId = gmf.PartyID -- Group Min Fee
			LEFT JOIN @Minfee m
				ON c.PartyId = m.PartyId
				AND c.ProductId = m.ProductId
				AND (c.FromDate BETWEEN m.FromDate AND m.ToDate
				OR c.ToDate BETWEEN m.FromDate AND m.ToDate
				OR m.FromDate BETWEEN c.FromDate AND c.ToDate
				OR m.ToDate BETWEEN c.FromDate AND c.ToDate
				)
				AND m.FeeTypeId = 1 -- Miniumfee
			LEFT JOIN @Minfee w
				ON c.PartyId = w.PartyId
				AND c.ProductId = w.ProductId
				AND (c.FromDate BETWEEN w.FromDate AND w.ToDate
				OR c.ToDate BETWEEN w.FromDate AND w.ToDate
				OR w.FromDate BETWEEN c.FromDate AND c.ToDate
				OR w.ToDate BETWEEN c.FromDate AND c.ToDate
				)
				AND w.FeeTypeId = 2 -- waive
			LEFT JOIN @Discount d
				ON d.PartyId = c.PartyId
				AND d.ProductId = c.ProductId
				AND (c.FromDate BETWEEN d.FromDate AND d.ToDate
				OR c.ToDate BETWEEN d.FromDate AND d.ToDate
				OR d.FromDate BETWEEN c.FromDate AND c.ToDate
				OR d.ToDate BETWEEN c.FromDate AND c.ToDate
				)
				AND d.DiscountGroupType IN (@DiscountIndividualFee, @DiscountIndividualGrosswin, @DiscountByGroupFee, @DiscountByGroupGrosswin) -- discount
			LEFT JOIN @Discount r
				ON r.PartyId = c.PartyId
				AND r.ProductId = c.ProductId
				AND (c.FromDate BETWEEN r.FromDate AND r.ToDate
				OR c.ToDate BETWEEN r.FromDate AND r.ToDate
				OR r.FromDate BETWEEN c.FromDate AND c.ToDate
				OR r.ToDate BETWEEN c.FromDate AND c.ToDate
				)
				AND r.DiscountGroupType = @Rebate
		WHERE ((@DiscountGroup = 0)
			OR (@DiscountGroup <> 0
			AND d.DiscountGroupId = @DiscountGroup
			AND d.DiscountGroupType IN (@DiscountIndividualFee, @DiscountIndividualGrosswin, @DiscountByGroupFee, @DiscountByGroupGrosswin)))
			AND ((@RebateGroup = 0)
			OR (@RebateGroup <> 0
			AND r.DiscountGroupId = @RebateGroup
			AND r.DiscountGroupType = @Rebate))
	)
	SELECT Result.*
	FROM Result
	INNER JOIN @ProductOrder po ON po.ProductId = Result.ProductId
	ORDER BY Result.PayerID, po.OrderNumber
	
	DROP TABLE #Temp_ChargeInfo
END
GO