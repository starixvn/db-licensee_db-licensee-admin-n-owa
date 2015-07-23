USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[LA_Inv_InvoiceAmountGenerate]   Script Date: 07/20/2015 09:12:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Inv_InvoiceAmountGenerate] 
	  @PartyId				INT
	, @FromDate				DATETIME
	, @ToDate				DATETIME
	, @ProductCode			VARCHAR(100)	
	, @ErrCode				INT				= 0		OUTPUT
	, @ErrMsg				NVARCHAR(1000)	= ''	OUTPUT
WITH RECOMPILE
AS
SET NOCOUNT ON
BEGIN
	-- Region Party Group Assignment
	DECLARE @PartyGroup AS TABLE (PartyId INT)
	INSERT INTO @PartyGroup(PartyId)
	(
	    SELECT PartyId 
		FROM bodb_licensee.dbo.LA_PartyGroupAssignment WITH(NOLOCK)
		WHERE PartyGroupId IN (	SELECT PartyGroupId 
								FROM bodb_licensee.dbo.LA_PartyGroupAssignment WITH(NOLOCK)
								WHERE PartyId = @PartyId)
	)
	
	IF (SELECT COUNT(*) FROM @PartyGroup) = 0 -- Party dont have Party Group.
	BEGIN 
		INSERT INTO @PartyGroup(PartyId) VALUES(@PartyId)
	END
	-- End region
	
	-- Region: Get party charge rate info
	DECLARE @PartyIdString VARCHAR(100)
	SELECT @PartyIdString = COALESCE(@PartyIdString + ', ', '') + CONVERT(VARCHAR(10), PartyId)
	FROM @PartyGroup 
	
	DECLARE @PartyChargeInfo AS TABLE (
		PartyId				INT
		, LicenseeId		INT
		, ProductID			INT
		, Rate				MONEY
		, FromDate			SMALLDATETIME
		, ToDate			SMALLDATETIME)

	INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, ProductID, Rate, Fromdate, Todate)
	(
		SELECT PartyID, LicenseeID, ProductID, DI_Rate, Fromdate, Todate
		FROM bodb_licensee.dbo.LA_f_ChargeInfo_xtest(@PartyIdString, @FromDate, @ToDate, @ProductCode, 'OA', 1)
		WHERE DI_Rate > 0 AND ProductId <> 1 --exclude RB
	)	
	--SELECT * FROM @PartyChargeInfo pci
	-- End region
	
	-- Region: Get base Currency
	DECLARE @BaseCurrencyId INT = 12
	DECLARE @BaseCurrencyName VARCHAR(5) = 'GBP'
	SET @BaseCurrencyId = ISNULL((	SELECT TOP 1 oci.BaseCurrencyId
									FROM bodb_licensee.dbo.OAS_ChargeInfo oci WITH(NOLOCK)	
									WHERE	oci.FromParty = @PartyId 
											AND(@FromDate BETWEEN oci.FromDate AND oci.ToDate 
												OR @ToDate BETWEEN oci.FromDate AND oci.ToDate
												OR (oci.FromDate < @FromDate AND @ToDate < oci.ToDate))
								), 12)
	
	DECLARE @BaseCurrencyTable AS TABLE(Id INT, Name VARCHAR(5))
	INSERT INTO @BaseCurrencyTable(Id,Name)
	EXECUTE bodb_Licensee.dbo.LA_SelBaseCurrency
	
	SELECT @BaseCurrencyName = Name
	FROM @BaseCurrencyTable bct
	WHERE @BaseCurrencyId = bct.Id	
	-- End Region
	
	-- Region: Validate the same base currency in ChargeInfo,MinFee & Discount/Rebate
	DECLARE @Month TINYINT = MONTH(@FromDate)
	DECLARE @FirstDate DATETIME = DATEADD(mm, DATEDIFF(mm, 0, @FromDate), 0)
	DECLARE @LastDate DATETIME = DATEADD (dd, -1, DATEADD(mm, DATEDIFF(mm, 0, @FromDate) + 1, 0))
	DECLARE @DaysInMonth INT = DATEDIFF(day, @FirstDate, @LastDate) + 1
	
	IF (SELECT COUNT(mf.CurrencyId)
		FROM bodb_licensee.dbo.LA_MinFee mf WITH(NOLOCK)
		WHERE (mf.FeeTypeId = 1 AND mf.CurrencyId = @BaseCurrencyId )
			AND mf.ProductId IN (SELECT ProductId FROM @PartyChargeInfo)
			AND ((mf.FromDate BETWEEN @FirstDate AND @LastDate) OR (mf.ToDate BETWEEN @FirstDate AND @LastDate) OR (mf.FromDate<@FirstDate AND @LastDate < mf.ToDate))
			AND (mf.PartyId = @PartyId OR mf.PartyId IN (SELECT PartyId FROM @PartyGroup))) = 0
	BEGIN
		SELECT @ErrCode=1, @ErrMsg='Wrong Base Currency'
		RETURN
	END		
	-- End Region
	
	-- Region: MinfeeGroup Date range	

	DECLARE @MinFeeGroup AS TABLE (
		FeeType		TINYINT,	
		PartyId		INT, 
		ProductId	TINYINT, 
		CurrencyId	INT,	
		FeeAmount	MONEY, 
		FromDate	DATETIME,	
		ToDate		DATETIME, 
		ActualFee	MONEY)
	
	INSERT INTO @MinFeeGroup(FeeType ,PartyId,ProductId, CurrencyId ,FeeAmount ,FromDate ,ToDate)
	(
		SELECT mf.FeeTypeId, mf.PartyId,mf.ProductId, mf.CurrencyId,mf.FeeAmount,
			CASE WHEN @FirstDate>= mf.FromDate THEN @FirstDate ELSE mf.FromDate END AS FromDate,
			CASE WHEN @LastDate < mf.ToDate THEN @LastDate ELSE mf.ToDate END AS ToDate
		FROM bodb_licensee.dbo.LA_MinFee mf WITH(NOLOCK)
		WHERE ((mf.FeeTypeId = 1 AND mf.CurrencyId = @BaseCurrencyId ) OR mf.FeeTypeId = 2)
			AND mf.ProductId IN (SELECT ProductId FROM @PartyChargeInfo)
			AND ((mf.FromDate BETWEEN @FirstDate AND @LastDate) OR (mf.ToDate BETWEEN @FirstDate AND @LastDate) OR (mf.FromDate<@FirstDate AND @LastDate < mf.ToDate))
			AND (mf.PartyId = @PartyId OR mf.PartyId IN (SELECT PartyId FROM @PartyGroup))						
	)
	
	-- Calculate actual min fee via prorate.
	UPDATE @MinFeeGroup
	SET mf.ActualFee =  mf.FeeAmount 
						* (@DaysInMonth - (	SELECT SUM(DATEDIFF(d, w.FromDate, w.ToDate) + 1)
											FROM @MinFeeGroup w
											WHERE FeeType = 2 AND mf.PartyId = w.PartyId AND mf.ProductId = w.ProductId))
						/ @DaysInMonth						
						
	FROM @MinFeeGroup mf
	WHERE mf.FeeType = 1
	
	UPDATE @MinFeeGroup
	SET mf.ActualFee =  mf.FeeAmount 						
	FROM @MinFeeGroup mf
	WHERE mf.FeeType = 1 AND mf.ActualFee IS NULL	
	SELECT * FROM @MinFeeGroup mfg
	-- End region
	
	-- Region: Get exchange rate info
	CREATE TABLE #Exchange ( 
		ExchangeDate	DATE, 
		ExchangeID		INT, 
		CurrencyCode	VARCHAR(10), 
		Rate			FLOAT)	
	
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)	
	-- End region
	
	-- Region: Get Amount by Product
	DECLARE @DrawFilter SMALLINT = 1	
		
	CREATE TABLE #TempData (
		LicenseeId		INT, 
		PartyId			INT, 
		rptDate			DATETIME, 
		CurrencyId		INT, 
		WinLoss			MONEY, 
		AComm			MONEY, 
		ProductId		TINYINT, 
		AmountToCompany MONEY, 
		ActualAmount	MONEY)
	INSERT INTO #TempData (LicenseeId,PartyId,rptDate,CurrencyId,WinLoss,AComm,ProductId)
	(
	    SELECT b.SiteID,p.PartyId, b.rptDate, b.CurrencyID				
			, SUM(ISNULL(b.MemberWL, 0)) Winloss					 			 					 				
			, SUM(ISNULL(b.CommissionA, 0)) AS AComm
			, p.ProductId
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			INNER JOIN @PartyChargeInfo p ON b.ProductId = p.ProductID 
												AND p.LicenseeId = b.SiteId
												AND b.rptDate BETWEEN p.FromDate AND p.ToDate
		WHERE b.rptDate BETWEEN @FromDate AND @ToDate			
			AND (b.CurrencyID <> 20)
			AND b.customercategory NOT IN (27, 28)					
		GROUP BY b.rptdate, b.SiteId, p.PartyId,b.CurrencyID, p.ProductId
	)
	CREATE NONCLUSTERED INDEX Idx_InvoiceData ON #TempData (PartyId, ProductId)
	
	UPDATE #TempData
	SET AmountToCompany =	CASE  
								WHEN td.ProductId = 3 THEN (-td.WinLoss * p.Rate - td.AComm) * e.Rate									
								WHEN td.ProductId <> 3 THEN (-td.WinLoss * p.Rate) * e.Rate
								ELSE 0 
							END
	FROM #TempData td INNER JOIN @PartyChargeInfo p ON td.LicenseeId = p.LicenseeId AND td.ProductId = p.ProductID
		INNER JOIN #Exchange e ON td.rptDate = e.ExchangeDate AND td.CurrencyId = e.ExchangeID
	
	--SELECT * FROM #TempData td
	-- End region
	
	-- Region: Check min fee group	
	CREATE TABLE #InvoiceData (
		PartyId			INT,
		ProductId		TINYINT, 
		InvoiceAmount	MONEY, 
		AmountType		TINYINT,
		IsApplyMinFee	BIT)
	
	DECLARE @AppliedMinFeeData AS TABLE (
		PartyId				INT, 
		ProductId			TINYINT, 
		AmountToCompany		MONEY, 
		AmountUnderWaive	MONEY,
		AmountUnderMinFee	MONEY,
		TotalMinFeeAmount	MONEY)
	
	;WITH SumAmout_Cte (PartyId, ProductId, AmountToCompany)
	AS
	(
		SELECT td.PartyId, td.ProductId, SUM(td.AmountToCompany) AS AmountToCompany			
		FROM #TempData td
		GROUP BY td.PartyId, td.ProductId
	)
	
	INSERT INTO @AppliedMinFeeData (PartyId,ProductId,AmountToCompany)
	(
	    SELECT mf.PartyId,cte.ProductId, cte.AmountToCompany					
	    FROM @MinFeeGroup mf INNER JOIN SumAmout_Cte cte ON mf.PartyId = cte.PartyId
	    WHERE	mf.FeeType = 2 
				AND mf.PartyId = @PartyId
	)
	
	UPDATE @AppliedMinFeeData
	SET AmountUnderWaive = ISNULL((	SELECT SUM(td.AmountToCompany)
									FROM #TempData td
									WHERE	mf.PartyId = td.PartyId 
											AND mf.ProductId = td.ProductId
											AND td.rptDate BETWEEN mf.FromDate AND mf.ToDate), 0)
	FROM @AppliedMinFeeData d INNER JOIN @MinFeeGroup mf ON mf.PartyId = d.PartyId AND mf.ProductId = d.ProductId
	WHERE	mf.FeeType = 2 
			AND mf.PartyId = @PartyId		
	
	UPDATE @AppliedMinFeeData
	SET AmountUnderWaive =	CASE 
								WHEN AmountUnderWaive IS NULL OR AmountUnderWaive<0 THEN 0 
								ELSE AmountUnderWaive 
							END,
		AmountUnderMinFee = CASE 
								WHEN ISNULL(AmountToCompany, 0) - ISNULL(AmountUnderWaive, 0) < 0 THEN 0 
								ELSE ISNULL(AmountToCompany, 0) - ISNULL(AmountUnderWaive, 0) 
							END
	
	UPDATE @AppliedMinFeeData
	SET d.TotalMinFeeAmount = ISNULL((	SELECT SUM(mf.ActualFee)
										FROM @MinFeeGroup mf
										WHERE	mf.FeeType = 1 
												AND d.PartyId = mf.PartyId	
												AND d.ProductId = mf.ProductId)
										, 0)
	FROM @AppliedMinFeeData d 
	--SELECT * FROM @AppliedMinFeeData mfd	
	
	INSERT INTO #InvoiceData(PartyId,ProductId,InvoiceAmount,AmountType,IsApplyMinFee)
	(
		SELECT d.PartyId, d.ProductId, 
			CASE 
				WHEN d.AmountUnderMinFee < d.TotalMinFeeAmount THEN d.TotalMinFeeAmount + d.AmountUnderWaive
				ELSE d.AmountUnderMinFee + d.AmountUnderWaive
			END AS InvoiceAmount,
			0 AS AmountType,
			CASE
				WHEN d.AmountUnderMinFee < d.TotalMinFeeAmount THEN 1
				ELSE 0
			END AS IsApplyMinFee
				
		FROM @AppliedMinFeeData d 
	)
	-- End region
	
	-- Region: Get discount group info
	DECLARE @DiscountGroupHeader AS TABLE (
		DiscountGroupId		INT, 
		DiscountGroupType	TINYINT, 
		CurrencyId			INT, 
		FromDate			DATETIME, 
		ToDate				DATETIME)
		
	INSERT INTO @DiscountGroupHeader(DiscountGroupId,DiscountGroupType,CurrencyId,FromDate,ToDate)
	(
		SELECT d.DiscountGroupId, t.DiscountGroupType,t.CurrencyId,d.FromDate,t.ToDate
		FROM bodb_Licensee.dbo.LA_DiscountGroupHeader d WITH(NOLOCK) INNER JOIN 
			(SELECT DiscountGroupType, CurrencyId, Max(ToDate) AS ToDate
			FROM bodb_Licensee.dbo.LA_DiscountGroupHeader dg WITH(NOLOCK)
			WHERE @FromDate<= ToDate AND FromDate<=@ToDate
			GROUP BY DiscountGroupType, dg.CurrencyId) t ON d.ToDate = t.ToDate
	)
	
	DECLARE @DiscountGroup AS TABLE(DiscountGroupId		SMALLINT,									
									DiscountGroupType	TINYINT,																		
									FromAmount			MONEY,
									ToAmount			MONEY,
									Rate				MONEY,
									ProductId			TINYINT)
		
	INSERT INTO @DiscountGroup (DiscountGroupId, DiscountGroupType, FromAmount, ToAmount, Rate, ProductId )	
	(
		SELECT dg.DiscountGroupId, dg.DiscountGroupType, dgd.FromAmount, dgd.ToAmount, dgd.Rate, dgp.ProductId
		FROM @DiscountGroupHeader dg 
			INNER JOIN bodb_Licensee.dbo.LA_DiscountGroupDetail dgd WITH(NOLOCK) ON dg.DiscountGroupId = dgd.DiscountGroupId
			INNER JOIN bodb_Licensee.dbo.LA_DiscountGroupProduct dgp WITH(NOLOCK) ON dg.DiscountGroupId = dgp.DiscountGroupId
			INNER JOIN bodb_Licensee.dbo.LA_DiscountGroupAssignment dga WITH(NOLOCK) ON dga.DiscountGroupId = dg.DiscountGroupId
		WHERE	dga.PartyID = @PartyId
				-- AND dg.CurrencyId = @BaseCurrencyId
				AND dgp.ProductId IN ( SELECT ProductId FROM #InvoiceData)			
	)
	-- End Region	
	
	-- Region: Apply Discount
	INSERT INTO #InvoiceData(PartyId, ProductId, InvoiceAmount, AmountType)
	(
	    SELECT iv.PartyId, iv.ProductId, iv.InvoiceAmount * dg.Rate AS InvoiceAmount, dg.DiscountGroupType AS AmountType
	    FROM #InvoiceData iv INNER JOIN @DiscountGroup dg ON iv.ProductId=dg.ProductId
	    WHERE ROUND(iv.InvoiceAmount - 0.5, 0) BETWEEN dg.FromAmount AND dg.ToAmount
			AND iv.IsApplyMinFee = 0
			AND dg.DiscountGroupType = 1
	)
	
	-- End Region
	
	-- Region: Apply Rebate
	INSERT INTO #InvoiceData(PartyId, ProductId, InvoiceAmount, AmountType)
	(
	    SELECT iv.PartyId, iv.ProductId, iv.InvoiceAmount * dg.Rate AS InvoiceAmount, dg.DiscountGroupType AS AmountType
	    FROM #InvoiceData iv INNER JOIN @DiscountGroup dg ON iv.ProductId=dg.ProductId
	    WHERE ROUND(iv.InvoiceAmount - ISNULL((SELECT SUM(id.InvoiceAmount)
										FROM #InvoiceData id
										WHERE iv.PartyId = id.PartyId 
											AND iv.ProductId = id.ProductId
											AND id.AmountType = 1
										), 0) 
									- 0.5, 0) BETWEEN dg.FromAmount AND dg.ToAmount
			AND iv.IsApplyMinFee = 0
			AND dg.DiscountGroupType = 2
			AND iv.AmountType = 0
	)
	
	SELECT id.ProductId,
		CASE 
			WHEN id.ProductId = 0 THEN 'SB' 
			ELSE p.ProductPrefix
			END AS ProductCode,
		CASE 
			WHEN id.ProductId = 0 THEN 'Sportbooks' 
			ELSE p.ProductName
			END AS ProductName,
		id.InvoiceAmount,
		id.AmountType
	FROM #InvoiceData id  LEFT JOIN bodb_licensee.dbo.Product3rd p ON id.ProductId = p.Productid
	-- End Region
	
	DROP TABLE #Exchange
	DROP TABLE #TempData
	DROP TABLE #InvoiceData
END