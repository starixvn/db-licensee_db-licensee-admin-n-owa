/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO

ALTER PROCEDURE [dbo].[LA_Inv_MultipleGenerationTemporaryInvoiceSel]
	@PartyIds			VARCHAR(MAX),
	@FromDate			DATE,
	@ToDate				DATE,
	@Environment		VARCHAR(10)
AS

/*	Header:
	Created: 2021.03.02 - Parsons
	Task : Support a function to export all invoices at once: Generate Multiple Temporary Invoice
	DB: DBLIC.bodb_Licensee
   
	Revisions: 
		- 20210302@Parsons: Create new sp [#147006]
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @ProductCodes VARCHAR(MAX)
	SELECT  @ProductCodes = COALESCE(@ProductCodes + ',', '') + ProductPrefix FROM dbo.Product3rd WITH (NOLOCK) WHERE ProductId NOT IN (16, 37) AND (EndOfSupportDate IS NULL OR EndOfSupportDate >= @FromDate) AND OfferSite IN (0, 2) -- Deposit only
	SELECT  @ProductCodes = 'SB' + ISNULL(',' + @ProductCodes, '')

	DECLARE @FinalResult TABLE (PartyId INT, InvoiceHeaderId BIGINT, InvoiceSymbol NVARCHAR(20), InvoiceNumber INT, BillerId INT, InvoiceType TINYINT, InvoicePath NVARCHAR(255), ProductCodes VARCHAR(MAX), LicensingFee MONEY, Discount MONEY)
	
	-- Region: Get Party Settings
	BEGIN
		DECLARE @PartySettings TABLE (IndexNumber INT, PartyId INT, LicenseeId INT, PartyName VARCHAR(50), BaseCurrencyId INT, BaseCurrencyName VARCHAR(10), InvoiceLanguage VARCHAR(50), InvoiceSymbol NVARCHAR(20), InvoiceNumber INT)
		INSERT INTO @PartySettings (IndexNumber, PartyId, LicenseeId, PartyName, BaseCurrencyId, BaseCurrencyName, InvoiceLanguage)
		SELECT i.[rank], p.PartyId, p.OldRefId, p.PartyName, ISNULL(bc.BaseCurrencyId, 6), ISNULL(e.Code, 'EUR'), pd.InvoiceLanguage
		FROM dbo.strSplit(@PartyIds, ',') i
			INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON p.PartyId = i.val
			LEFT JOIN OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyId = p.PartyId
			LEFT JOIN OAS_PartyBaseCurrency bc WITH (NOLOCK) ON p.PartyId = bc.PartyId AND bc.FromDate <= @ToDate AND bc.ToDate >= @FromDate
			LEFT JOIN bodb02.dbo.Exchange e WITH (NOLOCK) ON e.ExchangeId = bc.BaseCurrencyId

		DECLARE @InvoiceSettings TABLE (PartyId INT, BillerId INT, InvTypeId SMALLINT, ProductCodes VARCHAR(200), InvTemplateName VARCHAR(50))
		INSERT INTO @InvoiceSettings (PartyId, BillerId, InvTypeId, InvTemplateName, ProductCodes)
		SELECT s.FromPartyId, s.ToPartyId, s.InvTypeId, t.InvTemplateName
			, STUFF((SELECT ',' + CASE WHEN ls.ProductId = 0 THEN 'SB' ELSE ProductPrefix END
						FROM dbo.LA_InvoiceSetting ls WITH (NOLOCK)
							LEFT JOIN dbo.Product3rd p WITH (NOLOCK) ON ls.ProductId = p.ProductId
						WHERE s.InvTypeId = ls.InvTypeId AND s.FromPartyId = ls.FromPartyId AND s.ToPartyId = ls.ToPartyId
							AND ls.InvTypeId = 1 AND ls.ProductId IS NOT NULL
						FOR XML PATH('')), 1, 1, '') AS ProductCodes
		FROM @PartySettings ps
			INNER JOIN dbo.LA_InvoiceSetting s WITH (NOLOCK) ON s.FromPartyId = ps.PartyId
			INNER JOIN dbo.LA_InvoiceTemplate t WITH (NOLOCK) ON s.InvTempId = t.InvTemplateId
		WHERE s.InvTypeId IN (1, 3, 6)
		GROUP BY s.FromPartyId, s.ToPartyId, s.InvTypeId, t.InvTemplateName
	END
	-- End Region: Get Party Settings

	-- Region: Get Exchange
	BEGIN
		DECLARE @BaseCurrencies TABLE (RowId SMALLINT IDENTITY(1, 1), BaseCurrencyId INT, BaseCurrencyName VARCHAR(10))
		CREATE TABLE #Exchange (ExchangeDate DATE, ExchangeId INT, CurrencyCode	VARCHAR(10), BaseCurrencyId INT, BaseCurrencyRate FLOAT)
		
		INSERT INTO @BaseCurrencies (BaseCurrencyId, BaseCurrencyName)
		SELECT DISTINCT BaseCurrencyId, BaseCurrencyName FROM @PartySettings

		INSERT INTO #Exchange (ExchangeDate, ExchangeId, CurrencyCode, BaseCurrencyId, BaseCurrencyRate)
		SELECT e.ExchangeDate, e.ExchangeId, e.Code, bc.BaseCurrencyId, e.BaseCurrencyRate
		FROM @BaseCurrencies bc
			CROSS APPLY bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, bc.BaseCurrencyName) e
	END
	-- End Region: Get Exchange

	-- Region: Get party's amount who were issued invoices
	BEGIN
		INSERT INTO @FinalResult (PartyId, InvoiceHeaderId, InvoiceSymbol, InvoiceNumber, BillerId, InvoiceType, InvoicePath, LicensingFee, Discount, ProductCodes)
		SELECT h.PartyId, h.InvoiceHeaderId, h.InvoiceSymbol, h.InvoiceNumber, h.BillerId, h.InvoiceType, h.InvoicePath, h.Amount - ISNULL(d.Discount, 0), ISNULL(Discount, 0)
			,STUFF((SELECT ',' + CASE WHEN s.ProductId = 0 THEN 'SB' ELSE p.ProductPrefix END
					FROM dbo.LA_InvoiceStatement s WITH (NOLOCK)
						LEFT JOIN dbo.Product3rd p WITH (NOLOCK) ON s.ProductId = p.ProductId
					WHERE h.InvoiceHeaderId = s.InvoiceHeaderId AND h.InvoiceType = 1 AND s.ProductId IS NOT NULL
					FOR XML PATH('')), 1, 1, '') AS ProductCodes
		FROM @PartySettings ps
			INNER JOIN dbo.LA_InvoiceHeader h WITH (NOLOCK) ON ps.PartyId = h.PartyId
			OUTER APPLY (
				SELECT SUM(ISNULL(s.Expense, 0)) AS Discount
				FROM dbo.LA_InvoiceStatement s WITH (NOLOCK)
				WHERE h.InvoiceHeaderId = s.InvoiceHeaderId AND h.InvoiceType = 1 AND s.InvItemTypeId = 4 -- Discount
			) d
		WHERE h.StatusId = 0 AND h.Environment = @Environment
			AND h.InvoiceType IN (1, 3, 8) -- Software Fee, Rebate, Hosting Fee
			AND (h.FromDate = @FromDate AND h.ToDate = @ToDate)
	END
	-- End Region: Get party's amount who were issued invoices

	-- Region: Get party's amount who were not issued invoices
	BEGIN
		DECLARE @SumByProducts TABLE (PartyId INT, ProductId INT, ProductCode VARCHAR(500), LicensingFee MONEY, Discount MONEY, Rebate MONEY)

		-- Region: Get amount to company, discount, rebate (only for some supported products)
		BEGIN
			CREATE TABLE #AmountToCompany (PartyId INT, ProductId INT, Fee MONEY, Discount MONEY, Rebate MONEY, IsChargedByMinFee BIT, IsChargedByGroupMinFee BIT)
			DECLARE @temp_PartyIds VARCHAR(500), @temp_BaseCurrencyId INT, @temp_BaseCurrencyName VARCHAR(10), @RowId SMALLINT = 1

			WHILE 1 = 1
			BEGIN
				SELECT @Temp_PartyIds = NULL, @temp_BaseCurrencyId = NULL, @temp_BaseCurrencyName = NULL
				SELECT @temp_BaseCurrencyId = BaseCurrencyId, @temp_BaseCurrencyName = BaseCurrencyName FROM @BaseCurrencies WHERE RowId = @RowId

				IF @temp_BaseCurrencyId IS NULL
					BREAK

				SELECT @temp_PartyIds = COALESCE(@temp_PartyIds + ',', '') + CAST(PartyId AS VARCHAR(20)) FROM @PartySettings WHERE BaseCurrencyId = @temp_BaseCurrencyId

				INSERT INTO #AmountToCompany(PartyId, ProductId, Fee, Discount, Rebate, IsChargedByMinFee, IsChargedByGroupMinFee)
				EXEC dbo.LA_AmountToCompanyByDiscountCurrencySel @FromDate, @ToDate, @temp_PartyIds, @ProductCodes, @temp_BaseCurrencyName, @temp_BaseCurrencyId
				
				SET @RowId = @RowId + 1
			END
		END
		-- End Region: Get amount to company, discount, rebate (only for some supported products)

		-- Region: Get amount to company for remaining products
		BEGIN
			-- Region: Party charge info
			BEGIN
				DECLARE @PartyChargeInfo TABLE (ChargeId INT, ChargeType INT, PartyId INT, LicenseeId INT, ProductId INT, BettypeRef INT, FromDate DATE, ToDate DATE, Rate FLOAT)
				INSERT INTO @PartyChargeInfo (ChargeId, ChargeType, PartyId, LicenseeId, ProductId, BettypeRef, FromDate, ToDate, Rate)
				SELECT ChargeId, ChargeType, PartyId, LicenseeId, ProductId, Bettype, FromDate, ToDate, DI_Rate
				FROM dbo.LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate, @ProductCodes, 'OA', 1)
				WHERE DI_Rate > 0

				-- Specific for CB
				DECLARE @MinCBDate DATE, @MaxCBDate DATE
				SELECT  @MinCBDate = MIN(FromDate), @MaxCBDate = MAX(ToDate) FROM @PartyChargeInfo WHERE ProductId = 15

				DECLARE @CBChargeRate TABLE (PartyId INT, LicenseeId INT, rptDate DATE, CommShareRate FLOAT, CashInShareRate FLOAT)
				;WITH CTE_rptDate AS (
					SELECT @MinCBDate AS rptDate
					UNION ALL SELECT DATEADD(DAY, 1, rptDate) FROM CTE_rptDate WHERE rptDate < @MaxCBDate
				)
				INSERT INTO @CBChargeRate (PartyId, LicenseeId, rptDate, CommShareRate, CashInShareRate)
				SELECT DISTINCT ISNULL(cr.PartyId, sr.PartyId), ISNULL(cr.LicenseeId, sr.LicenseeId), r.rptDate, ISNULL(cr.Rate, 0), ISNULL(sr.Rate, 0)
				FROM CTE_rptDate r
					LEFT JOIN @PartyChargeInfo cr ON r.rptDate BETWEEN cr.FromDate AND cr.ToDate AND cr.ProductId = 15 AND cr.ChargeType = 6
					LEFT JOIN @PartyChargeInfo sr ON r.rptDate BETWEEN sr.FromDate AND sr.ToDate AND sr.ProductId = 15 AND sr.ChargeType = 7
				WHERE cr.ProductId IS NOT NULL OR sr.ProductId IS NOT NULL
				OPTION (MAXRECURSION 0)

				DELETE @PartyChargeInfo WHERE ProductId = 15
			END
			-- End region: Party charge info

			-- Region: Get Win Loss Data
			BEGIN
				CREATE TABLE #TempData (
					LicenseeId INT, rptDate DATE, ProductId INT, BettypeRef INT DEFAULT(-1), CurrencyId INT
					,MemberWL MONEY DEFAULT(0), MemberComm MONEY DEFAULT(0), AgentWL MONEY DEFAULT(0), AgentComm MONEY DEFAULT(0)
					,Contribution MONEY DEFAULT(0), JackpotPrize MONEY DEFAULT(0), ExtraAmount MONEY DEFAULT(0), OddsSpread MONEY DEFAULT(0)
					,PayOut MONEY DEFAULT(0), CommShare MONEY DEFAULT(0), CashInShare MONEY DEFAULT(0)
				)

				CREATE TABLE #tmpResult (PartyId INT, ProductId INT, rptDate DATE, LicenseeAmount MONEY, ExtraAmount MONEY DEFAULT(0), IsApplyMinFee BIT DEFAULT (1))
				
				-- CO
				DECLARE @FDate SMALLDATETIME = @FromDate, @TDate SMALLDATETIME = @ToDate
				INSERT INTO #TempData (LicenseeId, rptDate, ProductId, CurrencyId, MemberWL, PayOut)
				SELECT r.SiteId, CONVERT(DATE, r.WinlostDate) AS rptDate, 25, r.Currency
					,SUM(r.BuyBackAmt) AS MemberWL
					,SUM(r.TicketPayout - r.BuyBackAmt - r.BABuyBackAmt) AS Payout
				FROM bodb_LicenseeReport.dbo.rptLicCashoutSummary r WITH (NOLOCK)
				WHERE r.WinlostDate BETWEEN @FDate AND @TDate
					AND r.Currency <> 20
					AND r.RoleId = 1 -- Member
				GROUP BY r.SiteId, CONVERT(DATE, r.WinlostDate), r.Currency
	
				INSERT INTO #TempData (LicenseeId, rptDate, ProductId, CurrencyId, BettypeRef, MemberWL, MemberComm, AgentWL, AgentComm, Contribution, JackpotPrize, ExtraAmount, OddsSpread, PayOut, CommShare, CashInShare)
				SELECT r.SiteId, r.rptDate, r.ProductId, r.CurrencyId
					,CASE WHEN r.Bettype IN (901, 1706, 3007) THEN r.Bettype ELSE ISNULL(sbr.BettypeRef, -1) END
					,SUM(CASE WHEN (r.ProductId IN (32, 43, 42) AND ISNULL(r.TicketType, 0) = 2) OR r.Bettype IN (902, 903, 904, 999, 4299, 4300, 4297, 4298, 1698, 1699, 1906) THEN 0 ELSE ISNULL(r.MemberWL, 0) END) AS MemberWL
					,SUM(ISNULL(r.CommissionP, 0)) AS MemberComm
					,SUM(ISNULL(r.GrossWL, 0)) AS AgentWL
					,SUM(ISNULL(r.CommissionA, 0)) AS AgentComm
					,SUM(CASE WHEN r.Bettype IN (4297, 1698) THEN ISNULL(-r.GrossWL, 0) ELSE 0 END) AS Contribution
					,SUM(CASE WHEN r.Bettype IN (4298, 1699) THEN ISNULL(r.MemberWL, 0) ELSE 0 END) AS JackpotPrize
					,SUM(CASE WHEN r.Bettype IN (4300, 4299, 1906) OR (r.ProductId IN (32, 43, 42) AND ISNULL(r.TicketType, 0) = 2) THEN ISNULL(r.MemberWL, 0) ELSE 0 END) AS ExtraAmount
					,SUM(CASE WHEN r.Bettype = 999 THEN ISNULL(-r.GrossWL, 0) ELSE 0 END) AS OddsSpread
					,SUM(CASE WHEN r.ProductId = 15 THEN ISNULL(r.Turnover, 0) - ISNULL(r.WinPrizeAmount, 0) - ISNULL(r.CashOutAmount, 0) ELSE 0 END) AS PayOut
					,SUM(CASE WHEN r.ProductId = 15 THEN CASE WHEN ISNULL(r.TicketType, 0) = 0 THEN ISNULL(r.Turnover, 0) ELSE ISNULL(r.ExtraAmount, 0) END ELSE 0 END) AS CommShare
					,SUM(CASE WHEN r.ProductId = 15 OR r.Bettype = 901 THEN ISNULL(r.BuyBackAmount, 0) ELSE 0 END) AS CashInShare
				FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct r WITH (NOLOCK)
					LEFT JOIN dbo.Sport_Bettype_Reference sbr WITH (NOLOCK) ON sbr.Bettype = r.Bettype
				WHERE r.rptDate BETWEEN @FromDate AND @ToDate
					AND r.StatusId NOT IN (-1, 101, 102, 103)
					AND r.CustomerCategory NOT IN (27, 28)
					AND r.CurrencyId <> 20
					AND r.ProductId <> 25 -- CO
				GROUP BY r.SiteId, r.rptDate, r.CurrencyId, r.ProductId
					,CASE WHEN r.Bettype IN (901, 1706, 3007) THEN r.Bettype ELSE ISNULL(sbr.BettypeRef, -1) END

				INSERT INTO #tmpResult (PartyId, ProductId, rptDate, LicenseeAmount, ExtraAmount)
				SELECT ps.PartyId, t.ProductId, t.rptDate
					,SUM((CASE
							WHEN t.BettypeRef IN (1706, 3007) THEN 0
							WHEN t.ProductId = 3 THEN -(t.MemberWL + t.AgentComm)
							WHEN (t.ProductId = 15 AND cp.LicenseeId IS NULL) OR (t.ProductId <> 15 AND p.LicenseeId IS NULL) THEN 0
							WHEN t.ProductId = 15 THEN t.PayOut - t.CommShare * cp.CommShareRate - t.CashInShare * cp.CashInShareRate
							ELSE (-MemberWL - Contribution) * ISNULL(cr.Rate, p.Rate) + PayOut + OddsSpread END
					) * e.BaseCurrencyRate) AS LicenseeAmount
					,SUM(CASE
							WHEN p.LicenseeId IS NULL THEN 0
							WHEN t.BettypeRef IN (1706, 3007) THEN -MemberWL * ISNULL(cr.Rate, p.Rate)
							ELSE (Contribution - JackpotPrize - ExtraAmount - CASE WHEN t.ProductId = 31 THEN (AgentComm + MemberComm) ELSE 0 END) * e.BaseCurrencyRate END
					) AS ExtraAmount
				FROM #TempData t
					INNER JOIN @PartySettings ps ON t.LicenseeId = ps.LicenseeId
					INNER JOIN #Exchange e ON t.CurrencyId = e.ExchangeId AND t.rptDate = e.ExchangeDate AND ps.BaseCurrencyId = e.BaseCurrencyId
					LEFT JOIN @CBChargeRate cp ON t.LicenseeId = cp.LicenseeId AND t.ProductId = 15 AND t.rptDate = cp.rptDate
					LEFT JOIN @PartyChargeInfo p ON t.LicenseeId = p.LicenseeId AND t.ProductId = p.ProductId AND t.BettypeRef = p.BettypeRef AND t.rptDate BETWEEN p.FromDate AND p.ToDate
					LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeId = p.ChargeId AND t.CurrencyId = cr.CurrencyId
				WHERE t.ProductId NOT IN (13, 37)
				GROUP BY ps.PartyId, t.ProductId, t.rptDate

				-- BT
				INSERT INTO #tmpResult (PartyId, ProductId, rptDate, LicenseeAmount)
				SELECT p.PartyId, 13, t.rptDate, SUM((CASE WHEN t.BettypeRef = 901 THEN -t.MemberWL WHEN t.ProductId = 13 THEN 0 ELSE t.MemberWL END - t.CashInShare * p.Rate) * e.BaseCurrencyRate) AS LicenseeAmount
				FROM #TempData t
					INNER JOIN @PartySettings ps ON t.LicenseeId = ps.LicenseeId
					INNER JOIN @PartyChargeInfo p ON t.LicenseeId = p.LicenseeId AND t.rptDate BETWEEN p.FromDate AND p.ToDate AND p.ProductId = 13
					INNER JOIN #Exchange e ON t.CurrencyId = e.ExchangeId AND t.rptDate = e.ExchangeDate AND ps.BaseCurrencyId = e.BaseCurrencyId
				WHERE t.ProductId IN (0, 3, 13)
				GROUP BY p.PartyId, t.rptDate

				-- SB Promotion
				INSERT INTO #tmpResult (PartyId, ProductId, rptDate, ExtraAmount)
				SELECT p.PartyId, 0, t.rptDate, -SUM(t.MemberWL * e.BaseCurrencyRate) AS ExtraAmount
				FROM #TempData t
					INNER JOIN @PartySettings ps ON t.LicenseeId = ps.LicenseeId
					INNER JOIN @PartyChargeInfo p ON t.LicenseeId = p.LicenseeId AND t.rptDate BETWEEN p.FromDate AND p.ToDate AND p.ProductId = 0
					INNER JOIN #Exchange e ON t.CurrencyId = e.ExchangeId AND t.rptDate = e.ExchangeDate AND ps.BaseCurrencyId = e.BaseCurrencyId
				WHERE t.ProductId = 37
				GROUP BY p.PartyId, t.rptDate
			END
			-- End Region: Get Win Loss Data
		END
		-- End Region: Get amount to company for remaining products

		-- Region: Sum data by Product
		BEGIN
			INSERT INTO @SumByProducts (PartyId, ProductId, ProductCode, LicensingFee, Discount, Rebate)
			SELECT r.PartyId, r.ProductId
				,CASE WHEN r.ProductId = 0 THEN 'SB' ELSE p.ProductPrefix END
				,CASE WHEN ISNULL(d.LicensingFee, r.LicensingFee) > 0 OR jvp.PartyId IS NOT NULL OR r.ProductId IN (3, 15, 25, 31) THEN ISNULL(d.LicensingFee, r.LicensingFee) ELSE 0 END + r.ExtraAmount
				,ISNULL(d.Discount, 0)
				,ISNULL(d.Rebate, 0)
			FROM (
				SELECT PartyId, ProductId, SUM(LicenseeAmount) AS LicensingFee, SUM(ExtraAmount) AS ExtraAmount
				FROM #tmpResult
				GROUP BY PartyId, ProductId
			) r
				LEFT JOIN (
					SELECT PartyId, ProductId, SUM(Fee) AS LicensingFee, SUM(Discount) AS Discount, SUM(Rebate) AS Rebate
					FROM #AmountToCompany
					GROUP BY PartyId, ProductId
				) d ON r.PartyId = d.PartyId AND r.ProductId = d.ProductId
				LEFT JOIN dbo.LA_f_JVPartyListSel() jvp ON r.PartyId = jvp.PartyId
				LEFT JOIN dbo.Product3rd p WITH (NOLOCK) ON r.ProductId = p.ProductId

			INSERT INTO @FinalResult (PartyId, BillerId, InvoiceType, ProductCodes, LicensingFee, Discount)
			SELECT s.PartyId, ivs.BillerId, 1, ivs.ProductCodes, SUM(s.LicensingFee), SUM(s.Discount)
			FROM @SumByProducts s
				INNER JOIN @InvoiceSettings ivs ON s.PartyId = ivs.PartyId AND ',' + ivs.ProductCodes LIKE '%,' + s.ProductCode + ',%' AND ivs.InvTypeId = 1 -- Software Fee
				LEFT JOIN @FinalResult r ON ivs.PartyId = r.PartyId AND ivs.BillerId = r.BillerId AND ivs.InvTypeId = r.InvoiceType
			WHERE r.PartyId IS NULL
			GROUP BY s.PartyId, ivs.BillerId, ivs.ProductCodes

			INSERT INTO @FinalResult (PartyId, BillerId, InvoiceType, LicensingFee)
			SELECT s.PartyId, ivs.BillerId, 3, -SUM(s.Rebate)
			FROM @SumByProducts s
				INNER JOIN @InvoiceSettings ivs ON s.PartyId = ivs.PartyId AND ivs.InvTypeId = 3 -- Rebate
				LEFT JOIN @FinalResult r ON ivs.PartyId = r.PartyId AND ivs.BillerId = r.BillerId AND ivs.InvTypeId = r.InvoiceType
			WHERE r.PartyId IS NULL AND s.Rebate > 0
			GROUP BY s.PartyId, ivs.BillerId
		END
		-- End Region: Sum data by Product

		-- Region: Get AMF, Prepayment and AGPrepayment
		BEGIN
			DECLARE @InvItemTypes TABLE (InvItemTypeId SMALLINT, InvItemTypeName VARCHAR(50))
			INSERT INTO @InvItemTypes (InvItemTypeId, InvItemTypeName)
			-- AdvanceMinFee (AMF)
			SELECT InvItemTypeId, 'AdvanceMinFee' AS InvItemTypeName
			FROM (VALUES (3), (5), (7), (21)) AS t (InvItemTypeId)
			-- Prepayment
			UNION ALL
			SELECT InvItemTypeId, 'AGPrepayment' AS InvItemTypeName
			FROM (VALUES (22), (23), (24)) AS t (InvItemTypeId)
			-- AGPrepayment
			UNION ALL
			SELECT InvItemTypeId, 'Prepayment' AS InvItemTypeName
			FROM (VALUES (25), (26), (27)) AS t (InvItemTypeId)

			DECLARE @InvAmount TABLE (PartyId INT, RemainingAMF MONEY, RemainingAGPrepayment MONEY, RemainingPrepayment MONEY)
			INSERT INTO @InvAmount (PartyId, RemainingAMF, RemainingAGPrepayment, RemainingPrepayment)
			SELECT r.PartyId
				,SUM(CASE WHEN r.InvItemTypeName = 'AdvanceMinFee'	THEN r.Amount ELSE 0 END) AS RemainingAMF
				,SUM(CASE WHEN r.InvItemTypeName = 'AGPrepayment'	THEN r.Amount ELSE 0 END) AS RemainingAGPrepayment
				,SUM(CASE WHEN r.InvItemTypeName = 'Prepayment'		THEN r.Amount ELSE 0 END) AS RemainingPrepayment
			FROM (
				SELECT p.PartyId, t.InvItemTypeName, SUM(ISNULL(s.Income, 0) - ISNULL(s.Expense, 0)) AS Amount
				FROM @PartyChargeInfo p
					INNER JOIN dbo.LA_InvoiceHeader h WITH (NOLOCK) ON p.PartyId = h.PartyId
					INNER JOIN dbo.LA_InvoiceStatement s WITH (NOLOCK) ON h.InvoiceHeaderId = s.InvoiceHeaderId
					INNER JOIN @InvItemTypes t ON s.InvItemTypeId = t.InvItemTypeId
				WHERE ISNULL(h.StatusId, 0) = 0 AND h.Environment = @Environment
				GROUP BY p.PartyId, t.InvItemTypeName
			) r
			GROUP BY r.PartyId

			-- AMF: SB only
			IF EXISTS (SELECT 1 FROM @InvAmount WHERE RemainingAMF > 0)
			BEGIN
				DECLARE @FirstDate DATETIME = DATEADD(MONTH, DATEDIFF(MONTH, 0, @FromDate), 0)
				DECLARE @LastDate DATETIME = DATEADD(MONTH, DATEDIFF(MONTH, -1, @FromDate), -1)
				DECLARE @DaysInMonth INT = DATEDIFF(DAY, @FirstDate, @LastDate) + 1

				DECLARE @MinFee TABLE (PartyId INT, FeeTypeId TINYINT, FeeAmount MONEY, ProrateMinFee MONEY, FromDate DATETIME, ToDate DATETIME)

				;WITH CTE_GroupMinFee AS (
					SELECT a.PartyId
					FROM bodb_Licensee.dbo.LA_GroupMinFeeAssignment a WITH (NOLOCK)
						INNER JOIN bodb_Licensee.dbo.LA_GroupMinFeeHeader h WITH (NOLOCK) ON a.GroupMinFeeId = h.GroupMinFeeId
					WHERE h.FromDate <= @LastDate AND h.ToDate >= @FirstDate
					GROUP BY a.PartyId
				)
				INSERT INTO @MinFee (PartyId, FeeTypeId, FeeAmount, FromDate, ToDate)
				SELECT m.PartyId, m.FeeTypeId, m.FeeAmount * e.BaseCurrencyRate
					,CASE WHEN @FromDate > FromDate THEN @FromDate ELSE FromDate END AS FromDate
					,CASE WHEN @ToDate < ToDate THEN @ToDate ELSE ToDate END AS ToDate
				FROM dbo.LA_MinFee m WITH (NOLOCK)
					INNER JOIN @InvAmount i ON m.PartyId = i.PartyId
					INNER JOIN @PartySettings ps ON m.PartyId = ps.PartyId
					INNER JOIN #Exchange e ON m.CurrencyId = e.ExchangeId AND e.BaseCurrencyId = ps.BaseCurrencyId AND e.ExchangeDate = @ToDate
					LEFT JOIN CTE_GroupMinFee gm ON m.PartyId = gm.PartyId
				WHERE m.FeeTypeId IN (1, 2)
					AND m.FromDate <= @LastDate AND m.ToDate >= @FirstDate
					AND m.ProductId = 0 -- SB
					AND gm.PartyId IS NULL -- not apply group min fee

				UPDATE m1
				SET m1.ProrateMinFee = (
							(
								SELECT TOP 1 m2.FeeAmount
								FROM @MinFee m2
								WHERE m2.FeeTypeId = 1 AND m1.PartyId = m2.PartyId
							) / (1.0 * @DaysInMonth / DATEDIFF(DAY, m1.FromDate, m1.ToDate) + 1))
				FROM @MinFee m1
				WHERE m1.FeeTypeId = 2

				UPDATE m1
				SET m1.ProrateMinFee = m1.FeeAmount / (1.0 * @DaysInMonth / (DATEDIFF(DAY, m1.FromDate, m1.ToDate) + 1))
										- ISNULL((
											SELECT SUM(m2.ProrateMinFee)
											FROM @MinFee m2
											WHERE m2.FeeTypeId = 2 AND m1.PartyId = m2.PartyId
											), 0)
				FROM @MinFee m1
				WHERE m1.FeeTypeId = 1

				DELETE @MinFee WHERE FeeTypeId = 2

				;WITH CTE_DeductedAMF AS (
					SELECT s.PartyId, ivs.BillerId, MIN(t.DeductedAMF) AS DeductedAMF
					FROM @SumByProducts s
						INNER JOIN @InvoiceSettings ivs ON s.PartyId = ivs.PartyId AND ',' + ivs.ProductCodes LIKE '%,' + s.ProductCode + ',%' AND ivs.InvTypeId = 1 -- Software Fee
						INNER JOIN @InvAmount i ON s.PartyId = i.PartyId AND i.RemainingAMF > 0
						INNER JOIN @MinFee m ON s.PartyId = m.PartyId AND m.ProrateMinFee > 0
						CROSS APPLY (
							SELECT s.LicensingFee AS DeductedAMF
							UNION ALL SELECT i.RemainingAMF
							UNION ALL SELECT m.ProrateMinFee
						) t
					WHERE s.ProductId = 0 -- SB
						AND s.LicensingFee > 0
					GROUP BY s.PartyId, ivs.BillerId
				)
				UPDATE f
				SET f.LicensingFee = f.LicensingFee - c.DeductedAMF
				FROM @FinalResult f
					INNER JOIN CTE_DeductedAMF c ON f.PartyId = c.PartyId AND f.BillerId = c.BillerId
				WHERE f.InvoiceType = 1 AND f.InvoiceHeaderId IS NULL
			END

			-- AG Prepayment: AG Casino
			IF EXISTS (SELECT 1 FROM @InvAmount WHERE RemainingAGPrepayment > 0)
			BEGIN
				;WITH CTE_DeductedAGPrepayment AS (
					SELECT s.PartyId, ivs.BillerId, MIN(t.DeductedAGPrepayment) AS DeductedAGPrepayment
					FROM @SumByProducts s
						INNER JOIN @InvoiceSettings ivs ON s.PartyId = ivs.PartyId AND ',' + ivs.ProductCodes LIKE '%,' + s.ProductCode + ',%' AND ivs.InvTypeId = 1 -- Software Fee
						INNER JOIN @InvAmount i ON s.PartyId = i.PartyId AND i.RemainingAGPrepayment > 0
						CROSS APPLY (
							SELECT s.LicensingFee AS DeductedAGPrepayment
							UNION ALL SELECT i.RemainingAGPrepayment
						) t
					WHERE s.ProductId = 10 -- AG Casino
						AND s.LicensingFee > 0
					GROUP BY s.PartyId, ivs.BillerId
				)
				UPDATE f
				SET f.LicensingFee = f.LicensingFee - c.DeductedAGPrepayment
				FROM @FinalResult f
					INNER JOIN CTE_DeductedAGPrepayment c ON f.PartyId = c.PartyId AND f.BillerId = c.BillerId
				WHERE f.InvoiceType = 1 AND f.InvoiceHeaderId IS NULL
			END

			-- Prepayment
			IF EXISTS (SELECT 1 FROM @InvAmount WHERE RemainingPrepayment > 0)
			BEGIN
				UPDATE f
				SET f.LicensingFee = f.LicensingFee - CASE WHEN c.RemainingPrepayment < f.LicensingFee THEN c.RemainingPrepayment ELSE f.LicensingFee END
				FROM @FinalResult f
					INNER JOIN @InvAmount c ON f.PartyId = c.PartyId AND c.RemainingPrepayment > 0
				WHERE f.InvoiceType = 1 AND f.InvoiceHeaderId IS NULL
			END
		END
		-- End Region: Get AMF, Prepayment and AGPrepayment
	END

	-- Region: Calc InvoiceNo
	BEGIN
		;WITH CTE_PartyInvoiceNo AS
		(
			SELECT ps.PartyId, iv.InvoiceSymbol, iv.InvoiceNumber
			FROM @PartySettings ps
				INNER JOIN @InvoiceSettings s ON s.PartyId = ps.PartyId
				CROSS APPLY
				(
					SELECT TOP 1 iv.InvoiceSymbol, MAX(iv.InvoiceNumber) InvoiceNumber
					FROM LA_InvoiceHeader iv WITH(NOLOCK)
					WHERE iv.StatusId = 0 AND iv.Environment = @Environment
							AND InvoiceType IN (1, 3, 8) -- Software Fee, Rebate, Hosting Fee
							AND iv.BillerId = s.BillerId
					GROUP BY iv.InvoiceSymbol, CreatedDateTime--, iv.PartyId, iv.BillerId, CreatedDateTime
					ORDER BY CreatedDateTime DESC
				) iv
		)
		UPDATE ps
		SET ps.InvoiceSymbol = c.InvoiceSymbol, ps.InvoiceNumber = c.InvoiceNumber
		FROM @PartySettings ps
			INNER JOIN cte_PartyInvoiceNo c ON ps.PartyId = c.PartyId
	END
	-- End Region: Calc InvoiceNo

	-- Region: Final Result
	BEGIN
		DECLARE @Result TABLE
		(
			RowIndex INT, IndexNumber INT, PartyId INT, PartyName VARCHAR(50), ItemType TINYINT, BillerId INT, BillerName NVARCHAR(50)
			,InvoiceHeaderId BIGINT, InvoiceSymbol NVARCHAR(20), InvoiceNumber INT, InvoicePath NVARCHAR(256)
			,BaseCurrencyId INT, BaseCurrencyName VARCHAR(10), InvoiceLanguage VARCHAR(50), ProductCodes VARCHAR(MAX)
			,LicensingFee MONEY, Discount MONEY, Rebate MONEY
		)

		INSERT INTO @Result
		(
			RowIndex, IndexNumber, PartyId, PartyName, ItemType, BillerId, BillerName, InvoiceHeaderId, InvoiceSymbol, InvoiceNumber, InvoicePath
			,BaseCurrencyId, BaseCurrencyName, InvoiceLanguage, ProductCodes, LicensingFee, Discount, Rebate
		)
		SELECT
			ROW_NUMBER() OVER(ORDER BY ps.IndexNumber) AS RowIndex
			,ps.IndexNumber
			,r.PartyId
			,ps.PartyName
			,r.InvoiceType AS ItemType
			,r.BillerId
			,b.BillerName
			,r.InvoiceHeaderId
			,ps.InvoiceSymbol
			,ISNULL(r.InvoiceNumber, ps.InvoiceNumber) AS InvoiceNumber
			,r.InvoicePath
			,ps.BaseCurrencyId
			,ps.BaseCurrencyName
			,ps.InvoiceLanguage
			,CASE WHEN r.InvoiceType = 1 THEN r.ProductCodes ELSE '' END AS ProductCodes
			,SUM(ISNULL(CASE WHEN r.InvoiceType = 3 THEN 0 ELSE r.LicensingFee END, 0)) AS LicensingFee
			,SUM(ISNULL(r.Discount, 0)) AS Discount
			,SUM(ISNULL(CASE WHEN r.InvoiceType = 3 THEN r.LicensingFee ELSE 0 END, 0)) AS Rebate
		FROM @FinalResult r
			INNER JOIN @PartySettings ps ON r.PartyId = ps.PartyId
			INNER JOIN DBCUST.bodb_Licensee.dbo.LA_BillerInfo b WITH (NOLOCK) ON r.BillerId = b.PartyId
		GROUP BY
			ps.IndexNumber
			,r.PartyId
			,ps.PartyName
			,r.InvoiceType
			,r.BillerId
			,b.BillerName
			,r.InvoiceHeaderId
			,ps.InvoiceSymbol
			,ISNULL(r.InvoiceNumber, ps.InvoiceNumber)
			,r.InvoicePath
			,ps.BaseCurrencyId
			,ps.BaseCurrencyName
			,ps.InvoiceLanguage
			,CASE WHEN r.InvoiceType = 1 THEN r.ProductCodes ELSE '' END

		;WITH cte_rowOrder AS(
			SELECT RowIndex, ROW_NUMBER() OVER (PARTITION BY BillerId ORDER BY BillerId) RowOrder
			FROM @Result r
			WHERE r.InvoiceHeaderId IS NULL
		)
		UPDATE r
		SET InvoiceNumber = r.InvoiceNumber + o.RowOrder
		FROM @Result r 
		INNER JOIN cte_rowOrder o  ON r.RowIndex = o.RowIndex
	END
	-- End Region: Final Result

	-- Return data
	SELECT RowIndex, IndexNumber, PartyId, PartyName, ItemType, BillerId, BillerName, InvoiceHeaderId, InvoiceSymbol, InvoiceNumber, InvoicePath
		,BaseCurrencyId, BaseCurrencyName, InvoiceLanguage, ProductCodes, LicensingFee, Discount, Rebate
	FROM @Result

	DROP TABLE #AmountToCompany
	DROP TABLE #Exchange
	DROP TABLE #TempData
	DROP TABLE #tmpResult
END
GO