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
	, @BaseCurrency			NVARCHAR(20)	= 'GBP'	OUTPUT
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
												OR (@FromDate < oci.FromDate AND @ToDate > oci.ToDate))
								), 12)
	
	DECLARE @BaseCurrencyTable AS TABLE(Id INT, Name VARCHAR(5))
	INSERT INTO @BaseCurrencyTable(Id,Name)
	EXECUTE bodb_Licensee.dbo.LA_SelBaseCurrency
	
	SELECT @BaseCurrencyName = Name
	FROM @BaseCurrencyTable bct
	WHERE @BaseCurrencyId = bct.Id	
	-- End Region	
	
	-- Region: MinfeeGroup Date range	
	DECLARE @Month TINYINT = MONTH(@FromDate)
	DECLARE @FirstDate DATETIME = DATEADD(mm, DATEDIFF(mm, 0, @FromDate), 0)
	DECLARE @LastDate DATETIME = DATEADD (dd, -1, DATEADD(mm, DATEDIFF(mm, 0, @FromDate) + 1, 0))
	DECLARE @DaysInMonth INT = DATEDIFF(day, @FirstDate, @LastDate) + 1
	
	--SELECT @FirstDate, @LastDate
	
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
		WHERE ((mf.FeeTypeId = 1 AND mf.CurrencyId = @BaseCurrencyId ) OR mf.FeeTypeId = 2 AND EXISTS ( SELECT PartyId 
																										FROM bodb_licensee.dbo.LA_MinFee m WITH(NOLOCK)
																										WHERE m.FeeTypeId = 1 
																											AND m.PartyId = mf.PartyId
																											AND m.CurrencyId = @BaseCurrencyId))					
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
	--SELECT * FROM @MinFeeGroup mfg
	-- End region
	
	-- Region: Validate the same base currency in ChargeInfo,MinFee & Discount/Rebate
	DECLARE @BaseCurrencyCheck TABLE(
		Party INT, 
		Product INT, 
		FeeType INT, 
		BaseCurrencyCount INT, 
		NonBaseCurrencyCount INT)
	
	INSERT INTO @BaseCurrencyCheck
	SELECT m.PartyId, m.ProductId, m.FeeTypeId,
		 SUM(CASE WHEN m.CurrencyId = @BaseCurrencyID THEN 1 ELSE 0 END) BaseCurrencyCount
		,SUM(CASE WHEN m.CurrencyId != @BaseCurrencyID THEN 1 ELSE 0 END) NonBaseCurrencyCount
	FROM bodb_licensee.dbo.LA_MinFee m WITH(NOLOCK)
	WHERE m.FeeTypeId = 1 AND m.PartyId IN (SELECT pg.PartyId FROM @PartyGroup pg)
		AND ((m.FromDate BETWEEN @FirstDate AND @LastDate) OR (m.ToDate BETWEEN @FirstDate AND @LastDate) OR (m.FromDate<@FirstDate AND @LastDate < m.ToDate))
	GROUP BY m.PartyId, m.ProductId, m.FeeTypeId	
	IF EXISTS(SELECT 1 FROM @BaseCurrencyCheck WHERE BaseCurrencyCount = 0 AND NonBaseCurrencyCount > 0)
	BEGIN
		SELECT @ErrCode = 1, @ErrMsg = 'Wrong currency setting on MinFee or Waive amount'
		RETURN
	END
	
	DELETE FROM @BaseCurrencyCheck
	INSERT INTO @BaseCurrencyCheck
	SELECT m.PartyId, m.ProductId, m.FeeType,
		 SUM(CASE WHEN m.CurrencyId = @BaseCurrencyID THEN 1 ELSE 0 END) BaseCurrencyCount
		,SUM(CASE WHEN m.CurrencyId != @BaseCurrencyID THEN 1 ELSE 0 END) NonBaseCurrencyCount
	FROM @MinFeeGroup m
	GROUP BY m.PartyId, m.ProductId, m.FeeType	
	
	IF EXISTS(SELECT 1 FROM @BaseCurrencyCheck WHERE BaseCurrencyCount = 0 AND NonBaseCurrencyCount > 0)
	BEGIN
		SELECT @ErrCode = 1, @ErrMsg = 'Wrong currency setting on MinFee or Waive amount'
		RETURN
	END
	-- End Region
	
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
	CREATE TABLE #TempData (
		LicenseeId		INT, 
		PartyId			INT, 
		rptDate			DATETIME, 
		CurrencyId		INT, 
		WinLoss			MONEY, 
		AComm			MONEY, 
		ProductId		TINYINT, 
		AmountToCompany MONEY)
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
	FROM #TempData td 
		INNER JOIN @PartyChargeInfo p ON td.LicenseeId = p.LicenseeId AND td.ProductId = p.ProductID
		INNER JOIN #Exchange e ON td.rptDate = e.ExchangeDate AND td.CurrencyId = e.ExchangeID
	
	--SELECT * FROM #TempData td	
	-- End region
	
	-- Region: Check min fee group	
	DECLARE @DateList AS TABLE(
		ProductId	INT,
		DateVal		DATETIME)
	INSERT INTO @DateList (ProductId,DateVal)
	(
	    SELECT a.ProductId, a.DateVal AS DateVal
	    FROM (
			SELECT m.ProductId, 
				m.FromDate AS DateVal
			FROM @MinFeeGroup m
			GROUP BY m.FromDate,m.ProductId,m.FeeType
			
			UNION 
			SELECT m.ProductId, 
				ToDate AS DateVal
			FROM @MinFeeGroup m
			GROUP BY m.ToDate,m.ProductId,m.FeeType
		) a		
	)	
	--SELECT * FROM @DateList
	
	DECLARE @MaxDate DATETIME
	SELECT @MaxDate = MAX(DateVal) FROM @DateList dl
	
	DECLARE @DateRange AS TABLE(
		ProductId	INT,
		FromDate	DATETIME,
		ToDate		DATETIME
	)
	
	INSERT INTO @DateRange(ProductId,FromDate,ToDate)
	(	
	    SELECT dl.ProductId,
			CASE WHEN ((SELECT COUNT(*) 
						FROM @MinFeeGroup mf 
						WHERE mf.FromDate = dl.DateVal AND mf.FeeType = 2 AND mf.ProductId = dl.ProductId) > 0)
					OR dl.DateVal = @FirstDate THEN dl.DateVal 
			ELSE (DATEADD(DAY,1,dl.DateVal))
			END	AS FromDate,
			CASE WHEN ((SELECT COUNT(*) 
						FROM @MinFeeGroup mf 
						WHERE mf.ToDate = MIN(dl2.DateVal) AND mf.FeeType = 2 AND mf.ProductId = dl.ProductId) > 0)
					OR MIN(dl2.DateVal) = @LastDate THEN MIN(dl2.DateVal)
			ELSE (DATEADD(DAY,-1,MIN(dl2.DateVal))) 
			END AS ToDate
	    FROM @DateList dl INNER JOIN @DateList dl2 ON dl2.DateVal > dl.DateVal AND dl2.ProductId = dl.ProductId
	    WHERE dl.DateVal < @MaxDate	    
	    GROUP BY dl.DateVal, dl.ProductId
	)
		    
	--SELECT * FROM @DateRange dr ORDER BY dr.ProductId, dr.FromDate
	
	CREATE TABLE #AppliedMinFee
	(
		PartyId			INT,
		ProductId		INT,
		FeeAmount		MONEY,		
		FromDate		DATETIME,
		ToDate			DATETIME,
		MinFeeProrate	MONEY,
		IsWaived		TINYINT,
		AmountToCompany	MONEY,
		ActualAmount	MONEY)	
	
	INSERT INTO #AppliedMinFee (PartyId,ProductId,FeeAmount,FromDate,ToDate)
	(
	    SELECT	mf.PartyId, 
				mf.ProductId, 
				mf.FeeAmount, 
				dr.FromDate, 
				dr.ToDate
	    FROM @MinFeeGroup mf INNER JOIN @DateRange dr ON mf.ProductId = dr.ProductId
	    WHERE mf.FeeType = 1
	)
	
	UPDATE #AppliedMinFee
	SET IsWaived =  CASE 
						WHEN am.FromDate >= mf.FromDate AND am.ToDate <= mf.ToDate THEN 1
						ELSE 0 
					END
	FROM @MinFeeGroup mf INNER JOIN #AppliedMinFee am ON mf.PartyId = am.PartyId AND mf.ProductId = am.ProductId
	WHERE mf.FeeType = 2
	
	UPDATE #AppliedMinFee
	SET MinFeeProrate = (FeeAmount / @DaysInMonth) * (DATEDIFF(DAY, FromDate, ToDate) + 1)	
	WHERE ISNULL(IsWaived, 0) = 0
	
	UPDATE #AppliedMinFee
	SET AmountToCompany = ISNULL((	SELECT SUM(td.AmountToCompany)							
									FROM #TempData td 
									WHERE amf.PartyId = td.PartyId
										AND amf.ProductId = td.ProductId
										AND td.rptDate BETWEEN amf.FromDate AND amf.ToDate), 0)
	FROM #AppliedMinFee amf
	
	UPDATE #AppliedMinFee
	SET ActualAmount = CASE 
						WHEN amf.IsWaived = 0 
							AND (	SELECT SUM(ISNULL(a1.AmountToCompany, 0))
									FROM #AppliedMinFee a1
									WHERE a1.FromDate = amf.FromDate 
										AND a1.ToDate = amf.ToDate)
									<
								(	SELECT SUM(ISNULL(a2.MinFeeProrate, 0))
									FROM #AppliedMinFee a2
									WHERE a2.FromDate = amf.FromDate 
										AND a2.ToDate = amf.ToDate)	
							AND amf.AmountToCompany < amf.MinFeeProrate
						THEN amf.MinFeeProrate
						ELSE amf.AmountToCompany
						END
	FROM #AppliedMinFee amf
	WHERE amf.PartyId = @PartyId
	
	--SELECT * FROM #AppliedMinFee amf ORDER BY amf.ProductId, amf.PartyId,  amf.FromDate
	
	CREATE TABLE #InvoiceData (
		PartyId			INT,
		ProductId		TINYINT, 
		InvoiceAmount	MONEY, 
		AmountType		TINYINT,
		IsApplyMinFee	BIT)
	
	INSERT INTO #InvoiceData(PartyId,ProductId,InvoiceAmount,AmountType,IsApplyMinFee)
	(
		SELECT	amf.PartyId, 
				amf.ProductId, 
				SUM(amf.ActualAmount), 
				0 AS AmountType, 
				CASE 
					WHEN SUM(amf.IsWaived) = 0 THEN 1 
					ELSE 0 
				END AS IsApplyMinFee
		FROM #AppliedMinFee amf
		WHERE amf.PartyId = @PartyId
		GROUP BY amf.PartyId, amf.ProductId		
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
		FROM bodb_Licensee.dbo.LA_DiscountGroupHeader d WITH(NOLOCK) 
			INNER JOIN (SELECT DiscountGroupType, CurrencyId, MAX(ToDate) AS ToDate
						FROM bodb_Licensee.dbo.LA_DiscountGroupHeader dg WITH(NOLOCK)
						WHERE @FromDate<= ToDate AND FromDate<=@ToDate
						GROUP BY DiscountGroupType, dg.CurrencyId) t ON d.ToDate = t.ToDate
	)
	
	DECLARE @DiscountGroup AS TABLE(
		DiscountGroupId		SMALLINT,									
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
				AND dg.CurrencyId = @BaseCurrencyId
				AND dgp.ProductId IN ( SELECT ProductId FROM #InvoiceData)			
	)
	-- End Region	
	
	-- Region: Apply Discount
	INSERT INTO #InvoiceData(PartyId, ProductId, InvoiceAmount, AmountType)
	(
	    SELECT iv.PartyId, iv.ProductId, iv.InvoiceAmount * dg.Rate AS InvoiceAmount, dg.DiscountGroupType AS AmountType
	    FROM #InvoiceData iv 
			INNER JOIN @DiscountGroup dg ON iv.ProductId=dg.ProductId
	    WHERE ROUND(iv.InvoiceAmount - 0.5, 0) BETWEEN dg.FromAmount AND dg.ToAmount
			AND iv.IsApplyMinFee = 0
			AND dg.DiscountGroupType = 1
	)
	
	-- End Region
	
	-- Region: Apply Rebate
	INSERT INTO #InvoiceData(PartyId, ProductId, InvoiceAmount, AmountType)
	(
	    SELECT iv.PartyId, iv.ProductId, iv.InvoiceAmount * dg.Rate AS InvoiceAmount, dg.DiscountGroupType AS AmountType
	    FROM #InvoiceData iv 
			INNER JOIN @DiscountGroup dg ON iv.ProductId=dg.ProductId
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
	FROM #InvoiceData id  
		LEFT JOIN bodb_licensee.dbo.Product3rd p ON id.ProductId = p.Productid
	-- End Region
	
	DROP TABLE #Exchange
	DROP TABLE #TempData
	DROP TABLE #AppliedMinFee
	DROP TABLE #InvoiceData
END