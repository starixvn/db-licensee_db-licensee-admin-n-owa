USE [bodb_Licensee]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Inv_InvoiceAmountGenerate]
	@PartyId			INT,
	@BillerId			INT,
	@InvoiceType		INT,
	@FromDate			DATETIME,
	@ToDate				DATETIME,
	@ProductCode		VARCHAR(100),	
	@ErrCode			INT				= 0		OUTPUT,
	@ErrMsg				NVARCHAR(1000)	= ''	OUTPUT,
	@BaseCurrency		NVARCHAR(20)	= 'GBP'	OUTPUT,
	@InvoiceTemplateName VARCHAR(200)	= ''	OUTPUT,
	@HostingFeesExchangeName VARCHAR(20)= ''	OUTPUT,
	@HostingFeesExchangeRate FLOAT		= 0		OUTPUT,
	@HostingFeesAmount MONEY			= 0		OUTPUT,
	@HostingFeesMaxPCU INT				= 0		OUTPUT,
	@IsWaived BIT						= 0		OUTPUT
WITH RECOMPILE
AS
/*	Header:
	Created: 2015.08.06 - Bravo.Tran
	Task : Create Invoice 
	DB: DB052.bodb_Licensee
   
	Revisions: 
		+ 2015.08.06 @Bravo.Tran: Invoice Amount - Generate
		+ 2015.09.22 @Bravo.Tran: Invoice Amount - Fix bug wrong Total amount under Discount.
		+ 2015.11.09 @Bravo.Tran: Invoice Amount - Enhance prorate min fee.
		+ 2016.06.27 @Bravo.Tran: Invoice Amount - Hosting Fess amount.
		+ 2016.07.19 @Bruce.Bui: Adding hosting fees extra info.
*/
/*	Example:
	USE bodb_Licensee
	DECLARE @FromDate DATETIME = '2016-06-01'
	DECLARE @ToDate DATETIME  = '2016-06-30'
	--DECLARE @FromDate DATETIME = '2012-11-01'
	--DECLARE @ToDate DATETIME  = '2012-11-30'
	--DECLARE @FromDate DATETIME = '2013-11-01'
	--DECLARE @ToDate DATETIME  = '2013-11-30'
	DECLARE @PartyId INT = 14
	DECLARE @BillerId INT = 150
	DECLARE @InvoiceType INT = 8
	DECLARE @ProductCode VARCHAR(100)='SB,BA,RB,NG,LC,VS,CS,BG,KN,PTCS,AGC,GD,VG,BT,MGC'
	DECLARE	@ErrCode INT
	DECLARE	@ErrMsg NVARCHAR(1000)
	DECLARE	@BaseCurrency NVARCHAR(20)
	DECLARE @InvoiceTemplateId VARCHAR(200)
	
	EXEC [LA_Inv_InvoiceAmountGenerate] @PartyId,@BillerId,@InvoiceType, @FromDate, @ToDate, @ProductCode, @ErrCode OUT, @ErrMsg OUT, @BaseCurrency OUT, @InvoiceTemplateId OUT
	SELECT @ErrCode, @ErrMsg, @BaseCurrency, @InvoiceTemplateId
*/
BEGIN
	SET NOCOUNT ON
	-- Region: Check Invoice Type is Rebate
	DECLARE @Month TINYINT = MONTH(@FromDate)
	DECLARE @FirstDate DATETIME = DATEADD(mm, DATEDIFF(mm, 0, @FromDate), 0)
	DECLARE @LastDate DATETIME = DATEADD (dd, -1, DATEADD(mm, DATEDIFF(mm, 0, @FromDate) + 1, 0))
	DECLARE @DaysInMonth INT = DATEDIFF(day, @FirstDate, @LastDate) + 1

	DECLARE @EmptyTable AS TABLE(
			ProductId	INT,
			ProductCode	VARCHAR(20),
			Productname	VARCHAR(200),
			InvoiceAmount MONEY,
			WithoutWaivedAmount MONEY,
			AmountType	TINYINT
	)

	-- Region: Get base Currency
	DECLARE @BaseCurrencyId INT = 12
	DECLARE @BaseCurrencyName VARCHAR(5) = 'GBP'
	SET		@BaseCurrencyId = ISNULL((	SELECT TOP 1 opd.BaseCurrencyId
										FROM dbo.OAS_PartyDetail opd WITH(NOLOCK)	
										WHERE	opd.PartyID = @PartyId
									), 12)
	
	DECLARE @BaseCurrencyTable AS TABLE(Id INT, Name VARCHAR(5))
	INSERT	INTO @BaseCurrencyTable(Id,Name)
	EXECUTE bodb_Licensee.dbo.LA_SelBaseCurrency
	
	SELECT	@BaseCurrencyName = Name
	FROM	@BaseCurrencyTable bct
	WHERE	@BaseCurrencyId = bct.Id
	
	SELECT @BaseCurrency = @BaseCurrencyName	
	-- End Region	

	-- Region: Get template
	SELECT @InvoiceTemplateName = ( SELECT	TOP 1 t.InvTemplateName
									FROM	dbo.LA_InvoiceSetting i 
											INNER JOIN dbo.LA_InvoiceTemplate t ON i.InvTempId = t.InvTemplateId
									WHERE	i.FromPartyId = @PartyId
											AND i.ToPartyId = @BillerId
											AND i.InvTypeId = @InvoiceType)
	-- End Region

	-- Region: Get exchange rate info
	CREATE	TABLE #Exchange ( 
			ExchangeDate	DATE, 
			ExchangeID		INT, 
			CurrencyCode	VARCHAR(10), 
			Rate			FLOAT)	
	
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
	
	-- End region
	
	DECLARE @InvoiceTypeHostingFeesId INT = (SELECT InvTypeId FROM dbo.LA_InvoiceType WHERE InvTypeName LIKE 'Hosting Fees')
	
	IF @InvoiceType = @InvoiceTypeHostingFeesId
	BEGIN
		-- Get charge rate settings
		DECLARE @Settings TABLE(
			ChargeId	INT,
			SettingType TINYINT,
			FromParty	INT, 
			FromDate	DATETIME, 
			ToDate		DATETIME,
			InputFromDate DATETIME,
			InputToDate DATETIME,
			DaysInMonth FLOAT,
			NumOfApplyDate	FLOAT,
			ProductName VARCHAR(50),
			FeesId		INT,
			FeesType	TINYINT,
			BaseProduct INT,
			IsSameExchange BIT
		)

		INSERT INTO @Settings(ChargeId, SettingType, FromParty, FromDate, ToDate, InputFromDate, InputToDate, DaysInMonth, ProductName, FeesId, FeesType, BaseProduct, IsSameExchange)
		SELECT s.ChargeId, s.SettingType, s.FromParty, s.FromDate, s.ToDate, @FromDate, @ToDate, @DaysInMonth, s.ProductName, f.HostingFeesId, f.HostingFeesTypeId, s.BasedMinimunFees,
			CASE WHEN s.BaseCurrencyId = f.BaseCurrencyId AND s.BaseCurrencyId = @BaseCurrencyId THEN 1 ELSE 0 END
		FROM dbo.LA_HostingFeesSetting s
			LEFT JOIN dbo.LA_HostingFees f ON s.HostingFeesId = f.HostingFeesId
		WHERE s.FromParty = @PartyId
			AND (@FromDate BETWEEN s.FromDate AND s.ToDate OR @ToDate BETWEEN s.FromDate AND s.ToDate)

		SET @ErrCode = 0
		IF EXISTS (SELECT TOP 1 * FROM @Settings WHERE IsSameExchange = 0 AND SettingType = 1 ORDER BY FromDate DESC)
		BEGIN
			SET @ErrCode = 80
			SET @ErrMsg = 'Please check the Exchange settings of Hosting Charge Rate. Exchange of the setting must be the same with Payer'' exchange'
		END
		ELSE
		BEGIN
			UPDATE @Settings
			SET NumOfApplyDate = CONVERT(MONEY, CASE WHEN InputToDate < ToDate THEN InputToDate ELSE ToDate END - CASE WHEN InputFromDate > FromDate THEN InputFromDate ELSE FromDate END) + 1

			-- if there is multiple setting, use the latest
			DECLARE @NumOfApplyDate INT = ISNULL((SELECT SUM(NumOfApplyDate) FROM @Settings WHERE SettingType = 1), 0)
			DELETE @Settings WHERE SettingType = 1 AND FromDate < (SELECT MAX(s.FromDate) FROM @Settings s WHERE s.SettingType=1)

			-- check waived status
			DECLARE @NumOfWaivedDays INT = ISNULL((SELECT SUM(NumOfApplyDate) FROM @Settings WHERE SettingType = 2), 0)
			SET @IsWaived = (CASE WHEN @NumOfWaivedDays > 0 THEN 1 ELSE 0 END)

			UPDATE @Settings
			SET NumOfApplyDate = @NumOfApplyDate - @NumOfWaivedDays
			WHERE SettingType = 1

			IF (SELECT COUNT(*) from @Settings WHERE SettingType = 1) = 0
			BEGIN 
				SET @ErrCode = 81
				SET @ErrMsg = 'There is no hosting fees charge rate settings!'
			END
			ELSE
			BEGIN
				DECLARE @FeesType TINYINT = (SELECT FeesType FROM @Settings WHERE SettingType = 1)
				IF @FeesType = 1 -- Fixed
				BEGIN
					INSERT INTO @EmptyTable
					SELECT p.Productid, p.ProductPrefix, s.ProductName, s.NumOfApplyDate/s.DaysInMonth * d.Amount * e.Rate, d.Amount * e.Rate, 0
					FROM @Settings s INNER JOIN dbo.Product3rd p ON s.ProductName = p.ProductName
						INNER JOIN dbo.LA_HostingFeesDetail d ON s.FeesId = d.HostingFeesId
						INNER JOIN #Exchange e ON d.BaseCurrencyId = e.ExchangeID AND e.ExchangeDate = @ToDate
					WHERE s.SettingType = 1
				END
				ELSE -- VCM
				BEGIN 
					DECLARE @CurrentUser TABLE (TotalUser INT, LogDate DATETIME)
					INSERT INTO @CurrentUser
					EXEC LA_PeakConcurrentUsersSel @PartyId, @FromDate, @ToDate

					-- If waive is applied then get max pcu out of waive range
					SET @HostingFeesMaxPCU = ISNULL((SELECT MAX(c.TotalUser) FROM @CurrentUser c WHERE c.TotalUser NOT IN (
						SELECT TotalUser FROM @CurrentUser c2 INNER JOIN @Settings s ON c2.LogDate BETWEEN s.FromDate AND s.ToDate WHERE s.SettingType = 2
					)),0)
					
					INSERT INTO @EmptyTable
					SELECT p.Productid, p.ProductPrefix, s.ProductName, s.NumOfApplyDate/s.DaysInMonth * d.Amount * e.Rate, d.Amount * e.Rate, 0
					FROM @Settings s INNER JOIN dbo.Product3rd p ON s.ProductName = p.ProductName
						INNER JOIN dbo.LA_HostingFeesDetail d ON s.FeesId = d.HostingFeesId AND @HostingFeesMaxPCU BETWEEN d.VCMFrom AND d.VCMTo
						INNER JOIN #Exchange e ON d.BaseCurrencyId = e.ExchangeID AND e.ExchangeDate = @ToDate
					WHERE s.SettingType = 1
				END

				SELECT TOP 1	@HostingFeesAmount = d.Amount,
								@HostingFeesExchangeName = e.CurrencyCode,
								@HostingFeesExchangeRate = e.Rate
				FROM @Settings s
					INNER JOIN dbo.LA_HostingFeesDetail d WITH(NOLOCK) ON s.FeesId = d.HostingFeesId
					INNER JOIN #Exchange e ON d.BaseCurrencyId = e.ExchangeID AND e.ExchangeDate = @ToDate
				WHERE s.SettingType = 1 AND (
					d.VCMFrom IS NULL OR @HostingFeesMaxPCU BETWEEN d.VCMFrom AND d.VCMTo
				)
			END
		END
		
		DECLARE @BaseProduct INT = (SELECT BaseProduct FROM @Settings WHERE SettingType = 2)
		SET @ProductCode = CASE 
			WHEN @BaseProduct = 0 THEN 'SB'
			ELSE (SELECT ProductPrefix FROM dbo.Product3rd WITH(NOLOCK) WHERE Productid = @BaseProduct)
		END
		
		IF (@ErrCode != 0 OR @BaseProduct IS NULL)
		BEGIN
			SELECT * FROM @EmptyTable
			DROP TABLE #Exchange
			RETURN
		END
	END
		
	IF @InvoiceType = 3 -- rebate
	BEGIN
		DECLARE @ProductCodeString VARCHAR(100) = ''
		SELECT  @ProductCodeString = @ProductCodeString + p.ProductCode + ','
		FROM(
				SELECT	CASE 
							WHEN dp.ProductId = 0 THEN 'SB'
							ELSE p.ProductPrefix 
						END AS ProductCode
				FROM	dbo.LA_DiscountGroupProduct dp WITH(NOLOCK)
						LEFT JOIN dbo.Product3rd p WITH(NOLOCK) ON dp.ProductId = p.Productid
						INNER JOIN dbo.LA_DiscountGroupHeader dh WITH(NOLOCK) ON dp.DiscountGroupId = dh.DiscountGroupId
						INNER JOIN dbo.LA_DiscountGroupAssignment da WITH(NOLOCK) ON dh.DiscountGroupId = da.DiscountGroupId
				WHERE	da.PartyID = @PartyId
						AND dh.DiscountGroupType = 2
			) p
				
		IF @ProductCodeString = '' OR @ProductCodeString = ','
		BEGIN
			SELECT @ErrCode = 1, @ErrMsg = 'There is no setting for Rebate in the Rebate Group. Please set it before proceeding further.'
			SELECT ProductId, ProductCode, ProductName, InvoiceAmount, AmountType FROM @EmptyTable
			RETURN
		END
		ELSE
		BEGIN
			SET @ProductCode = SUBSTRING(@ProductCodeString, 1, LEN(@ProductCodeString) - 1)
		END
	END	
	-- EndRegion
	
	-- Region Party Group Assignment
	DECLARE @PartyGroup AS TABLE (PartyId INT)
	INSERT	INTO @PartyGroup(PartyId)
	(
		SELECT	PartyId 
		FROM	dbo.LA_PartyGroupAssignment WITH(NOLOCK)
		WHERE	PartyGroupId IN (	SELECT	PartyGroupId 
									FROM	dbo.LA_PartyGroupAssignment WITH(NOLOCK)
									WHERE	PartyId = @PartyId)
	)
	
	IF (SELECT COUNT(*) FROM @PartyGroup) = 0 -- Party dont have Party Group.
	BEGIN 
		INSERT INTO @PartyGroup(PartyId) VALUES(@PartyId)
	END
	-- End region
	
	-- Region: Get party charge rate info
	DECLARE	@PartyIdString VARCHAR(100)
	SELECT	@PartyIdString = COALESCE(@PartyIdString + ', ', '') + CONVERT(VARCHAR(10), PartyId)
	FROM	@PartyGroup 
	
	DECLARE @PartyChargeInfo AS TABLE (
			PartyId		INT,
			LicenseeId	INT,
			ProductID	INT,
			BettypeRef  INT,
			Rate		MONEY,
			FromDate	SMALLDATETIME,
			ToDate		SMALLDATETIME)

	INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, ProductID, BettypeRef, Rate, Fromdate, Todate)
	(
		SELECT	PartyID, LicenseeID, ProductID, Bettype, DI_Rate, Fromdate, Todate
		FROM	dbo.LA_f_ChargeInfo(@PartyIdString, @FromDate, @ToDate, @ProductCode, 'OA', 1)
		WHERE	DI_Rate > 0 AND ProductId <> 1 --exclude RB
	)

	-- End region
	
	-- Region: MinfeeGroup Date range	
		
	DECLARE @MinFeeGroup TABLE(
			FeeType			TINYINT,
			PartyId			INT,
			ProductId		INT,
			CurrencyId		INT,
			FeeAmount		MONEY,		
			FromDate		DATETIME,
			ToDate			DATETIME,
			MinFeeProrate	MONEY,
			WaivedAmount	MONEY,
			TotalAmount		MONEY,		
			MinFeeAmount	MONEY,
			AmountToCompany	MONEY,
			IsApplyMinFee	BIT)
	
	INSERT INTO @MinFeeGroup(FeeType ,PartyId,ProductId, CurrencyId ,FeeAmount ,FromDate ,ToDate)
	(
		SELECT	mf.FeeTypeId, 
				mf.PartyId,
				mf.ProductId, 
				mf.CurrencyId,
				mf.FeeAmount,
				CASE WHEN @FromDate >= mf.FromDate THEN @FromDate ELSE mf.FromDate END AS FromDate,
				CASE WHEN @ToDate < mf.ToDate THEN @ToDate ELSE mf.ToDate END AS ToDate
		FROM	dbo.LA_MinFee mf WITH(NOLOCK)
		WHERE   ((mf.FeeTypeId = 1 AND mf.CurrencyId = @BaseCurrencyId ) 
					OR mf.FeeTypeId = 2 AND EXISTS (SELECT	PartyId 
													FROM	dbo.LA_MinFee m WITH(NOLOCK)
													WHERE	m.FeeTypeId = 1 
															AND m.PartyId = mf.PartyId
															AND m.ProductId = mf.ProductId
															AND m.CurrencyId = @BaseCurrencyId
															AND ((m.FromDate BETWEEN @FirstDate AND @LastDate) 
																OR (m.ToDate BETWEEN @FirstDate AND @LastDate) 
																OR (m.FromDate<@FirstDate AND @LastDate < m.ToDate)
															)
													)
				)					
				AND mf.ProductId IN (SELECT ProductId FROM @PartyChargeInfo)
				AND ((mf.FromDate BETWEEN @FirstDate AND @LastDate) 
					OR (mf.ToDate BETWEEN @FirstDate AND @LastDate) 
					OR (mf.FromDate<@FirstDate AND @LastDate < mf.ToDate)
				)
				AND (mf.PartyId = @PartyId OR mf.PartyId IN (SELECT PartyId FROM @PartyGroup))
	)
	
	DELETE	FROM @MinFeeGroup
	WHERE	ProductID NOT IN (SELECT ProductId FROM @MinFeeGroup WHERE [@MinFeeGroup].PartyId = @PartyId)	
			OR (FeeType = 2 AND (FromDate > ToDate))
	-- End region
	
	-- Region: Get discount group info
	DECLARE @DiscountGroupHeader AS TABLE (
			DiscountGroupId		INT, 
			DiscountGroupType	TINYINT,
			PartyId				INT, 
			CurrencyId			INT, 
			FromDate			DATETIME, 
			ToDate				DATETIME)
		
	INSERT INTO @DiscountGroupHeader(DiscountGroupId,DiscountGroupType,PartyId,CurrencyId,FromDate,ToDate)
	(
		SELECT	dg.DiscountGroupId,dg.DiscountGroupType,dga.PartyId, dg.CurrencyId, dg.FromDate, dg.ToDate
		FROM	bodb_Licensee.dbo.LA_DiscountGroupHeader dg WITH(NOLOCK)
				INNER JOIN bodb_Licensee.dbo.LA_DiscountGroupAssignment dga WITH(NOLOCK) ON dga.DiscountGroupId = dg.DiscountGroupId
		WHERE	@FromDate<= ToDate AND FromDate<=@ToDate
				AND dga.PartyID = @PartyId		
	)
	
	DELETE	FROM @DiscountGroupHeader
	WHERE	ToDate < (SELECT	MAX(ToDate)
					FROM	@DiscountGroupHeader
					WHERE	DiscountGroupType = 1)
			AND DiscountGroupType = 1
	DELETE	FROM @DiscountGroupHeader
	WHERE	ToDate < (SELECT	MAX(ToDate)
					FROM	@DiscountGroupHeader
					WHERE	DiscountGroupType = 2)
			AND DiscountGroupType = 2
	
	DECLARE @DiscountGroup AS TABLE(
			DiscountGroupId		SMALLINT,									
			DiscountGroupType	TINYINT,																		
			FromAmount			MONEY,
			ToAmount			MONEY,
			Rate				MONEY,
			PartyId				INT,		
			ProductId			TINYINT,
			BaseCurrency		INT)

	INSERT INTO @DiscountGroup (DiscountGroupId, DiscountGroupType, FromAmount, ToAmount, Rate, PartyId, ProductId , BaseCurrency)	
	(
		SELECT	dg.DiscountGroupId, 
				dg.DiscountGroupType, 
				dgd.FromAmount, 
				dgd.ToAmount, 
				dgd.Rate,
				dg.PartyID,
				dgp.ProductId, 
				dg.CurrencyId
		FROM	@DiscountGroupHeader dg 
				INNER JOIN bodb_Licensee.dbo.LA_DiscountGroupDetail dgd WITH(NOLOCK) ON dg.DiscountGroupId = dgd.DiscountGroupId
				INNER JOIN bodb_Licensee.dbo.LA_DiscountGroupProduct dgp WITH(NOLOCK) ON dg.DiscountGroupId = dgp.DiscountGroupId
				
		WHERE	dgp.ProductId IN ( SELECT DISTINCT ProductId FROM @PartyChargeInfo)			
	)
	-- End Region	
	
	-- Region: Validate the same base currency in ChargeInfo,MinFee & Discount/Rebate	
	DECLARE @BaseCurrencyCheck TABLE(
			Party INT, 
			Product INT, 
			FeeType INT, 
			BaseCurrencyCount INT, 
			NonBaseCurrencyCount INT)
	
	INSERT INTO @BaseCurrencyCheck
	SELECT	m.PartyId, 
			m.ProductId, 
			m.FeeTypeId,
			SUM(CASE WHEN m.CurrencyId = @BaseCurrencyID THEN 1 ELSE 0 END) BaseCurrencyCount,
			SUM(CASE WHEN m.CurrencyId != @BaseCurrencyID THEN 1 ELSE 0 END) NonBaseCurrencyCount
	FROM	dbo.LA_MinFee m WITH(NOLOCK)
	WHERE	m.FeeTypeId = 1 AND m.PartyId IN (SELECT pg.PartyId FROM @PartyGroup pg)
			AND ((m.FromDate BETWEEN @FirstDate AND @LastDate) 
				OR (m.ToDate BETWEEN @FirstDate AND @LastDate) 
				OR (m.FromDate<@FirstDate AND @LastDate < m.ToDate)
			)
	GROUP BY m.PartyId, m.ProductId, m.FeeTypeId	
	
	IF EXISTS(SELECT 1 FROM @BaseCurrencyCheck WHERE BaseCurrencyCount = 0 AND NonBaseCurrencyCount > 0)
	BEGIN
		SELECT @ErrCode = 1, @ErrMsg = 'Please check the Exchange settings of Payer&rsquo;s minfee or minfee group. Exchange of minfee or minfees in group should be the same with Payer&rsquo;s exchange.'
		SELECT ProductId, ProductCode, ProductName, InvoiceAmount, AmountType FROM @EmptyTable
		RETURN
	END
		
	DELETE FROM @BaseCurrencyCheck	
	INSERT INTO @BaseCurrencyCheck(Party, Product, BaseCurrencyCount, NonBaseCurrencyCount)
	SELECT	d.PartyId, 
			d.ProductId,
			SUM(CASE WHEN d.BaseCurrency = @BaseCurrencyID THEN 1 ELSE 0 END) BaseCurrencyCount,
			SUM(CASE WHEN d.BaseCurrency != @BaseCurrencyID THEN 1 ELSE 0 END) NonBaseCurrencyCount
	FROM	@DiscountGroup d
	WHERE	d.DiscountGroupType = 1
	GROUP BY d.PartyId, d.ProductId
	
	IF EXISTS(SELECT 1 FROM @BaseCurrencyCheck WHERE BaseCurrencyCount = 0 AND NonBaseCurrencyCount > 0)
	BEGIN
		SELECT @ErrCode = 2, @ErrMsg = 'Please check the Exchange settings of Payer&rsquo;s discount. Exchange of discount must be the same with Payer&rsquo;s exchange.'
		SELECT ProductId, ProductCode, ProductName, InvoiceAmount, AmountType FROM @EmptyTable
		RETURN
	END
	
	DELETE FROM @DiscountGroup
	WHERE (BaseCurrency != @BaseCurrencyId AND DiscountGroupType = 1)
	
	-- End Region	
		
	-- Region: Get Amount by Product
	CREATE	TABLE #TempData (
			LicenseeId		INT, 
			PartyId			INT, 
			rptDate			DATETIME, 
			CurrencyId		INT, 
			WinLoss			MONEY, 
			AComm			MONEY, 
			ProductId		TINYINT,
			BettypeRef		INT, 
			AmountToCompany MONEY,
			IsApplyMinFee	BIT)
	INSERT INTO #TempData (LicenseeId,PartyId,rptDate,CurrencyId,WinLoss,AComm,ProductId,BettypeRef)
	(
		SELECT	b.SiteID,
				p.PartyId, 
				b.rptDate, 
				b.CurrencyID, 
				SUM(ISNULL(b.MemberWL, 0)) Winloss, 
				SUM(ISNULL(b.CommissionA, 0)) AS AComm, 
				p.ProductId,
				r.BettypeRef
		FROM	bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				LEFT JOIN dbo.Sport_Bettype_Reference r ON b.Bettype = r.Bettype
				INNER JOIN @PartyChargeInfo p ON	b.ProductId = p.ProductID 
													AND p.LicenseeId = b.SiteId
													AND (b.Bettype = -1 OR r.BettypeRef = p.BettypeRef)
													AND b.rptDate BETWEEN p.FromDate AND p.ToDate
		WHERE	b.rptDate BETWEEN @FromDate AND @ToDate			
				AND (b.CurrencyID <> 20)
				AND b.customercategory NOT IN (27, 28)
				AND b.Bettype NOT IN (901,902,903)
		GROUP BY b.rptdate, b.SiteId, p.PartyId,b.CurrencyID, p.ProductId, r.BettypeRef
	)
	
	CREATE NONCLUSTERED INDEX Idx_InvoiceData ON #TempData (PartyId, ProductId)

	UPDATE	#TempData
	SET		AmountToCompany =	CASE  
									WHEN td.ProductId = 3 THEN (-td.WinLoss * p.Rate - td.AComm) * e.Rate									
									WHEN td.ProductId <> 3 THEN (-td.WinLoss * p.Rate) * e.Rate
									ELSE 0 
								END
	FROM	#TempData td 
			INNER JOIN @PartyChargeInfo p 
				ON td.LicenseeId = p.LicenseeId 
				AND ((td.ProductId = p.ProductID AND td.ProductId NOT IN (SELECT DISTINCT Productid FROM dbo.LA_Product3rdSub))
						OR 
					(td.ProductId = p.ProductID AND td.BettypeRef = p.BettypeRef AND td.ProductId IN (SELECT DISTINCT Productid FROM dbo.LA_Product3rdSub)))
				AND td.rptDate BETWEEN p.FromDate AND p.ToDate
			INNER JOIN #Exchange e ON td.rptDate = e.ExchangeDate AND td.CurrencyId = e.ExchangeID	
		
	UPDATE  t
	SET		t.IsApplyMinFee = 0
	FROM	#TempData t INNER JOIN @MinFeeGroup m ON t.rptDate BETWEEN m.FromDate AND m.ToDate
			AND t.ProductId = m.ProductId
			AND t.PartyId = m.PartyId
	WHERE	m.FeeType=2
	-- End region	
	
	-- Region: Check min fee group			
	--- calculate waived prorate (*)
	UPDATE	amf
	SET		MinFeeProrate = ((	SELECT	TOP 1 mfg.FeeAmount
								FROM	@MinFeeGroup mfg
								WHERE	mfg.FeeType = 1
										AND mfg.PartyId = amf.PartyId
										AND mfg.ProductId = amf.ProductId)
							/ @DaysInMonth) * (DATEDIFF(DAY, FromDate, ToDate) + 1)	
	FROM	@MinFeeGroup amf
	WHERE	FeeType = 2
	
	--- sum amount under waived	
	UPDATE	amf	
	SET		amf.WaivedAmount = ISNULL((	SELECT	SUM(td.AmountToCompany)							
										FROM	#TempData td 
										WHERE	amf.PartyId = td.PartyId
												AND amf.ProductId = td.ProductId
												AND td.rptDate BETWEEN amf.FromDate AND amf.ToDate), 0)
	FROM	@MinFeeGroup amf
	WHERE	amf.FeeType = 2
			
	--- calculate min fee prorate (fee amount in month - waived amount (*)
	UPDATE	amf
	SET		amf.MinFeeProrate = ROUND((	amf.FeeAmount / @DaysInMonth) * (DATEDIFF(DAY, FromDate, ToDate) + 1) - 
										ISNULL((SELECT	SUM(f.MinFeeProrate)							
												FROM	@MinFeeGroup f
												WHERE	f.FeeType = 2
														AND amf.PartyId = f.PartyId
														AND amf.ProductId = f.ProductId), 0), 2),
			amf.WaivedAmount =  ISNULL((SELECT	CASE WHEN SUM(f.WaivedAmount) < 0 THEN 0 ELSE SUM(f.WaivedAmount) END
										FROM	@MinFeeGroup f
										WHERE	f.FeeType = 2
												AND amf.PartyId = f.PartyId
												AND amf.ProductId = f.ProductId), 0),	
			amf.MinFeeAmount =  ISNULL((SELECT	SUM(td.AmountToCompany)							
										FROM	#TempData td 
										WHERE	amf.PartyId = td.PartyId
												AND td.rptDate BETWEEN amf.FromDate AND amf.ToDate
												AND td.IsApplyMinFee IS NULL
												AND amf.ProductId = td.ProductId), 0)
	FROM	@MinFeeGroup amf
	WHERE	amf.FeeType = 1
	--- sum min fee amount
	UPDATE	amf
	SET		amf.TotalAmount =  amf.MinFeeAmount + amf.WaivedAmount
	FROM	@MinFeeGroup amf
	WHERE	amf.FeeType = 1
	
	DECLARE @TotalMinFees TABLE(
		ProductId			INT,
		TotalMinFee			MONEY,
		TotalMinFeeAmount	MONEY
	)
	INSERT	INTO @TotalMinFees(ProductId, TotalMinFee)
	SELECT	mf.ProductId,
			SUM(MinFeeProrate)
	FROM	@MinFeeGroup mf
	WHERE	mf.FeeType = 1
	GROUP BY mf.ProductId
	
	UPDATE	t
	SET		TotalMinFeeAmount = ISNULL((	SELECT	SUM(mf.MinFeeAmount)
											FROM	@MinFeeGroup mf
											WHERE	mf.MinFeeAmount > 0
													AND FeeType = 1
													AND mf.ProductId = t.ProductId), 0)
	FROM	@TotalMinFees t
			
	--- calculate amount to company
	UPDATE	amf
	SET		amf.AmountToCompany =	CASE 
										WHEN t.TotalMinFeeAmount < t.TotalMinFee AND amf.MinFeeAmount < amf.MinFeeProrate 
											THEN amf.MinFeeProrate + amf.WaivedAmount
										ELSE amf.TotalAmount
									END,
			amf.IsApplyMinFee	=	CASE 
										WHEN t.TotalMinFeeAmount < t.TotalMinFee AND amf.MinFeeAmount < amf.MinFeeProrate 
											THEN 1
										ELSE 0
									END
	FROM	@MinFeeGroup amf INNER JOIN @TotalMinFees t ON amf.ProductId = t.ProductId
	WHERE	amf.FeeType = 1

	DECLARE @InvoiceData	TABLE(
			PartyId			INT,
			ProductId		INT, 
			InvoiceAmount	MONEY, 
			AmountType		TINYINT,
			Rate			MONEY)
		
	IF @InvoiceType = @InvoiceTypeHostingFeesId
	BEGIN 
		DECLARE @IsApplyMinFee BIT = ISNULL((SELECT TOP 1 IsApplyMinFee FROM @MinFeeGroup WHERE PartyId = @PartyId AND FeeType=1),0)

		-- Apply Min fee => Not waived
		-- No Min fee => waived
		SET @IsWaived = (CASE WHEN @IsApplyMinFee = 1 THEN 0 ELSE 1 END)

		IF @IsWaived = 0 AND @FeesType = 2 -- VCM and not waive then re-calculate max PCU
		BEGIN
			SET @HostingFeesMaxPCU =ISNULL((SELECT MAX(TotalUser) FROM @CurrentUser),0)
			
			DELETE @EmptyTable

			INSERT INTO @EmptyTable
			SELECT p.Productid, p.ProductPrefix, s.ProductName, 0, d.Amount * e.Rate, 0
			FROM @Settings s INNER JOIN dbo.Product3rd p ON s.ProductName = p.ProductName
				INNER JOIN dbo.LA_HostingFeesDetail d ON s.FeesId = d.HostingFeesId AND @HostingFeesMaxPCU BETWEEN d.VCMFrom AND d.VCMTo
				INNER JOIN #Exchange e ON d.BaseCurrencyId = e.ExchangeID AND e.ExchangeDate = @ToDate
			WHERE s.SettingType = 1

			SELECT TOP 1	@HostingFeesAmount = d.Amount,
							@HostingFeesExchangeName = e.CurrencyCode,
							@HostingFeesExchangeRate = e.Rate
			FROM @Settings s
				INNER JOIN dbo.LA_HostingFeesDetail d WITH(NOLOCK) ON s.FeesId = d.HostingFeesId
				INNER JOIN #Exchange e ON d.BaseCurrencyId = e.ExchangeID AND e.ExchangeDate = @ToDate
			WHERE s.SettingType = 1 AND (@HostingFeesMaxPCU BETWEEN d.VCMFrom AND d.VCMTo)
		END

		SELECT ProductId,
			ProductCode,
			Productname,
			CASE WHEN @IsWaived = 1
				THEN InvoiceAmount
				ELSE WithoutWaivedAmount
			END AS InvoiceAmount,
			AmountType
		FROM @EmptyTable
	END
	ELSE
	BEGIN
		INSERT INTO @InvoiceData(PartyId,ProductId,InvoiceAmount,AmountType)
		(
			SELECT	amf.PartyId, 
					amf.ProductId, 
					SUM(amf.AmountToCompany), 
					0 AS AmountType
			FROM	@MinFeeGroup amf
			WHERE	amf.PartyId = @PartyId
					AND amf.FeeType = 1
			GROUP	BY amf.PartyId, amf.ProductId
		)
	
		INSERT INTO @InvoiceData(PartyId,ProductId,InvoiceAmount,AmountType)
		(
			SELECT	td.PartyId, 
					td.ProductId, 
					SUM(td.AmountToCompany), 
					0 AS AmountType
			FROM	#TempData td 
			WHERE	td.PartyId = @PartyId AND td.ProductId NOT IN (SELECT td2.ProductId FROM @MinFeeGroup td2)
			GROUP	BY td.PartyId, td.ProductId		
		)
		-- End region
	
		-- Region: Apply Discount
		DECLARE @TotalAmountDiscount MONEY = (	SELECT SUM(CASE WHEN i.InvoiceAmount < 0 THEN 0 ELSE i.InvoiceAmount END) 
												FROM @InvoiceData i 
												WHERE i.ProductId IN (SELECT ProductId FROM @DiscountGroup d WHERE d.DiscountGroupType = 1))
		DELETE	FROM @DiscountGroup
		WHERE	@TotalAmountDiscount NOT BETWEEN [@DiscountGroup].FromAmount AND [@DiscountGroup].ToAmount
				AND [@DiscountGroup].DiscountGroupType = 1
	
		INSERT INTO @InvoiceData(PartyId, ProductId, InvoiceAmount, AmountType, Rate)
		(
			SELECT	iv.PartyId, iv.ProductId, iv.InvoiceAmount * dg.Rate AS InvoiceAmount, dg.DiscountGroupType AS AmountType, dg.Rate
			FROM	@InvoiceData iv INNER JOIN @DiscountGroup dg ON iv.ProductId=dg.ProductId
			WHERE	dg.DiscountGroupType = 1
		)	
		-- End Region
		
		-- Region: Apply Rebate
		INSERT INTO @InvoiceData(PartyId, ProductId, InvoiceAmount, AmountType, Rate)
		(
			SELECT	iv.PartyId, 
					iv.ProductId, 
					(iv.InvoiceAmount - ISNULL((SELECT	SUM(i.InvoiceAmount)
												FROM	@InvoiceData i
												WHERE	i.AmountType = 1
														AND i.ProductId = iv.ProductId), 0))
						* dg.Rate AS InvoiceAmount, 
					dg.DiscountGroupType AS AmountType, 
					dg.Rate
			FROM	@InvoiceData iv 
					INNER JOIN @DiscountGroup dg ON iv.ProductId=dg.ProductId
			WHERE	dg.DiscountGroupType = 2
					AND iv.AmountType = 0
		)
	
		-- End Region
	
		-- Region: Select data	
		DECLARE	@FinalResult TABLE(
				ProductId		INT,
				ProductCode		VARCHAR(100),
				ProductName		VARCHAR(500),
				InvoiceAmount	MONEY,
				AmountType		TINYINT,
				Rate			MONEY)
	
		INSERT INTO @FinalResult(ProductId,ProductCode,ProductName,InvoiceAmount,AmountType,Rate)
		(
			SELECT	id.ProductId,
					CASE 
						WHEN id.ProductId = 0 THEN 'SB' 
						ELSE p.ProductPrefix
						END AS ProductCode,
					CASE 
						WHEN id.ProductId = 0 THEN 'Sportsbook' 
						ELSE p.ProductName
						END AS ProductName,
					CASE
						WHEN id.InvoiceAmount > 0 OR id.ProductId = 3 THEN id.InvoiceAmount
						ELSE 0
					END AS InvoiceAmount,
					id.AmountType,
					id.Rate
			FROM	@InvoiceData id  
					LEFT JOIN dbo.Product3rd p WITH(NOLOCK) ON id.ProductId = p.Productid				
		)
	
		INSERT INTO @FinalResult(ProductId,ProductCode,ProductName,InvoiceAmount,AmountType,Rate)
		(
			SELECT	-1,
					(	SELECT	f.ProductCode + ',' 
						FROM	@FinalResult f 
						WHERE f.AmountType = id.AmountType FOR XML PATH('')) 
					AS ProductCode,
					(	SELECT	f.ProductName + ',' 
						FROM	@FinalResult f 
						WHERE f.AmountType = id.AmountType FOR XML PATH('')) 
					AS ProductName,
					SUM(id.InvoiceAmount),
					id.AmountType,
					id.Rate
			FROM	@FinalResult id  				
			WHERE	id.AmountType > 0
			GROUP BY id.AmountType, id.Rate
		)	
		UPDATE	@FinalResult
		SET		ProductCode = LEFT(ProductCode, LEN(ProductCode) - 1),
				ProductName = LEFT(ProductName, LEN(ProductName) - 1)
		WHERE	ProductId = -1
		
		SELECT	f.ProductId,
				f.ProductCode,
				f.ProductName,
				f.InvoiceAmount,
				f.AmountType,
				f.Rate
		FROM	@FinalResult f
		WHERE	(@InvoiceType != 3 AND (f.AmountType = 0 OR (f.ProductId = -1 AND f.AmountType = 1)))
				OR (@InvoiceType = 3 AND f.ProductId = -1 AND f.AmountType = 2)
		ORDER BY f.AmountType, f.ProductId
	END

	SELECT @ErrCode = 0, @ErrMsg = ''

	DROP TABLE #Exchange
	DROP TABLE #TempData

END
GO
GRANT EXECUTE ON [dbo].[LA_Inv_InvoiceAmountGenerate] TO bodbAdminNet