USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_PayerSettingSel]
  @PayerId			INT = 0
 ,@PayerGroup		INT = 0
 ,@DiscountGroup	INT = 0
 ,@RebateGroup		INT = 0
AS
/*
  Created: 20150420@Florent
  Task : Get Payer setting
  DB: DB052.bodb_Licensee

  Revisions:
  - 20150703@Florent: store BaseCurrencyId from OAS_ChargeInfo to OAS_PartyDetail
  - 20161025@Scofield: exclude Colossus Bet from ChargeInfo
  - 20161031@bruce.bui: include CB, charge type
  - 20170208@bruce.bui: include terminated licensees

  Params:
  + @PayerId : 0 get all Party
     <> 0 specify Party
  + @@PayerGroup : 0 get all Party
       <> 0 specify Party
  + @@DiscountGroup : 0 get all Party
       <> 0 specify Party
  + @@RebateGroup : 0 get all Party
       <> 0 specify Party
  Example:

*/
BEGIN
	SET NOCOUNT ON
	DECLARE @ProductListAll VARCHAR(100) = '',
			@ListParty VARCHAR(500) = '',
			@MinDate DATE,
			@MaxDate DATE,
			@CurrentDate DATE
	SET @CurrentDate = CONVERT(DATE, GETDATE())
	DECLARE @ChargeInfo AS TABLE(ChargeId INT, PartyId INT, PartyName VARCHAR(100), PartyGroupId INT, PartyGroupName VARCHAR(100), ProductId INT, ProductName VARCHAR(100),
			BettypeRef INT,Rate MONEY, FromDate DATE, ToDate DATE, FirstBilling VARCHAR(100), ExchangeID INT, ExchangeName VARCHAR(50), ChargeType TINYINT)
	CREATE TABLE #Temp_ChargeInfo(ChargeId INT, PartyID INT, ProductID INT, BettypeRef INT,Rate MONEY, Fromdate DATE, Todate DATE)

	DECLARE @Minfee AS TABLE(PartyId INT, ProductId INT, FeeTypeId TINYINT, FeeAmount MONEY, FromDate DATE, ToDate DATE)
	DECLARE @Discount AS TABLE(PartyId INT, ProductId INT, FromDate DATE, ToDate DATE, DiscountGroupId INT, FromAmount MONEY, ToAmount MONEY, Rate MONEY, DiscountGroupName VARCHAR(100), DiscountGroupType TINYINT)
	DECLARE @ChargeDetail AS TABLE(ChargeID INT, PartyID INT, ProductID INT, BettypeRef INT,DI_Rate MONEY, Fromdate DATE, Todate DATE)

	--Get list licensee,
	SELECT	@ListParty = @ListParty + CAST(p.PartyID AS VARCHAR) + ','
	FROM	dbo.OAS_Party p WITH (NOLOCK)
			INNER JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK)
				ON p.PartyID = pd.PartyID
			LEFT JOIN dbo.LA_PartyGroupAssignment pga WITH (NOLOCK)
				ON p.PartyID = pga.PartyId
	WHERE	PartyType = 1
			AND pd.IsDeposit = 1
			AND (@PayerId = 0
			OR p.PartyID = @PayerId)
			AND (@PayerGroup = 0
			OR pga.PartyGroupId = @PayerGroup)

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

	INSERT INTO @ChargeDetail (ChargeID, PartyID, ProductID, BettypeRef, DI_Rate, Fromdate, Todate)
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
			Todate
		FROM dbo.LA_f_ChargeInfo(@ListParty, @MinDate, @MaxDate, @ProductListAll, 'OA', 1)

	INSERT INTO #Temp_ChargeInfo (ChargeID, PartyID, ProductID, BettypeRef, Rate, Fromdate, Todate)
		SELECT
			b.ChargeID,
			a.PartyID,
			a.ProductID,
			b.BettypeRef,
			b.DI_Rate,
			a.Fromdate,
			a.Todate
		FROM (	SELECT
						c.PartyID,
						c.ProductID,
						MAX(c.Fromdate) AS Fromdate,
						MAX(c.Todate) AS Todate
				FROM	@ChargeDetail c
				WHERE	@CurrentDate BETWEEN c.Fromdate AND c.Todate
				GROUP BY	c.PartyID,
							c.ProductID) a
		INNER JOIN @ChargeDetail b
			ON a.PartyID = b.PartyID
			AND a.ProductID = b.ProductID
			AND a.Fromdate = b.Fromdate
			AND a.Todate = b.Todate

	INSERT INTO @ChargeInfo (ChargeId, PartyId, PartyName, PartyGroupId, PartyGroupName, ProductId, ProductName, BettypeRef, Rate, FromDate, ToDate, FirstBilling, ExchangeID, ExchangeName, ChargeType)
		SELECT
			c.ChargeID,
			c.PartyID,
			CASE
				WHEN ISNULL(pd.BrandName, '') != '' THEN pd.BrandName
				ELSE p.PartyName
			END AS PartyName,
			pg.PartyGroupId,
			pg.PartyGroupName,
			c.ProductID,
			pr.ProductName,
			c.BettypeRef,
			c.Rate,
			c.Fromdate,
			c.Todate,
			CASE WHEN c.ProductID IN (14,17) THEN s.FirstOfBilling ELSE ci.FirstOfBilling END,
			pd.BaseCurrencyId,
			ISNULL(e.Code, '') AS ExchangeName,
			ci.ChargeType
		FROM #Temp_ChargeInfo c
			INNER JOIN OAS_Party p WITH (NOLOCK) ON c.PartyID = p.PartyID
			INNER JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyID = pd.PartyID
			LEFT JOIN dbo.LA_PartyGroupAssignment pga WITH (NOLOCK) ON c.PartyID = pga.PartyId
			LEFT JOIN dbo.LA_PartyGroup pg WITH (NOLOCK) ON pga.PartyGroupId = pg.PartyGroupId
			INNER JOIN dbo.LA_f_Products3rd('') pr ON c.ProductID = pr.ProductID
			INNER JOIN dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON c.ChargeID = ci.ChargeID
			LEFT JOIN dbo.OAS_ChargeInfoSub s WITH(NOLOCK) ON ci.ChargeID = s.ChargeIdRef
			LEFT JOIN bodb02.dbo.Exchange e WITH (NOLOCK) ON pd.BaseCurrencyId = e.exchangeid
		WHERE @CurrentDate BETWEEN c.Fromdate AND c.Todate

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
			FROM bodb02.dbo.strSplit(@ListParty, ',')
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
						FROM bodb02.dbo.strSplit(@ListParty, ',')
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

	--result
	SELECT DISTINCT
		c.PartyId		AS PayerID,
		PartyName		AS PayerName,
		PartyGroupId	AS PayerGroupID,
		PartyGroupName	AS PayerGroupName,
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
			AND d.DiscountGroupType = 1 -- discount
		LEFT JOIN @Discount r
			ON r.PartyId = c.PartyId
			AND r.ProductId = c.ProductId
			AND (c.FromDate BETWEEN r.FromDate AND r.ToDate
			OR c.ToDate BETWEEN r.FromDate AND r.ToDate
			OR r.FromDate BETWEEN c.FromDate AND c.ToDate
			OR r.ToDate BETWEEN c.FromDate AND c.ToDate
			)
			AND r.DiscountGroupType = 2 -- rebate
	WHERE ((@DiscountGroup = 0)
		OR (@DiscountGroup <> 0
		AND d.DiscountGroupId = @DiscountGroup
		AND d.DiscountGroupType = 1))
		AND ((@RebateGroup = 0)
		OR (@RebateGroup <> 0
		AND r.DiscountGroupId = @RebateGroup
		AND r.DiscountGroupType = 2))
	ORDER BY c.PartyId, c.ProductId
END
DROP TABLE #Temp_ChargeInfo

GO
GRANT VIEW DEFINITION ON [dbo].[LA_PayerSettingSel] TO [vnteam]
GRANT EXECUTE ON [dbo].[LA_PayerSettingSel] TO bodbAdminNet