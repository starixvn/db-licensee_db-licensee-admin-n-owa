USE [bodb02]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Rpt_MuayThaiWinLoss]
	  @PartyIds				VARCHAR(1000)
	, @FromDate				DATETIME
	, @ToDate				DATETIME	
	, @BaseCurrencyName		VARCHAR(3)		= 'GBP'
WITH RECOMPILE
AS
/*  Created: 20160128@Forrest		
	Task : Report - Muay Thai Win Loss
	DB: DBEXT/bodb02
	Revisions:  			
	Param's Explanation:  						
*/
SET NOCOUNT ON
BEGIN
	DECLARE @Data As TABLE (
	SiteId					VARCHAR(50),
	CurrencyId				INT,
	WinLossDate				DATETIME,
	TotalTrans				INT,
	Turnover				MONEY,
	CustomerWinLoss			MONEY, 
	WinLossShare			MONEY, 
	LicenseeComm			MONEY, 
	ShareComm				MONEY)
	
	DECLARE @Result AS TABLE (
	ParentId				INT,
	ParentName				VARCHAR(50),
	PartyId					INT,
	PartyName				VARCHAR(50),
	CurrencyId				INT,
	CurrencyName			VARCHAR(50),
	WinLossDate				DATETIME,
	TotalTrans				INT, 
	Turnover				MONEY, 
	CustomerWinLoss			MONEY, 
	WinLossShare			MONEY, 
	LicenseeComm			MONEY, 
	ShareComm				MONEY, 
	AmountDueTo				MONEY)
	
	DECLARE @Exchange AS TABLE (
	ExchangeId				INT,
	ExchangeDate			DATETIME,
	Code					VARCHAR(3),
	Base					MONEY, 
	MYR						MONEY,
	USD						MONEY,
	EUR						MONEY,
	CNY						MONEY,
	GBP						MONEY)
	
	DECLARE @GrandTotal AS TABLE (
	CurrencyName			VARCHAR(3), 
	TotalTrans				INT, 
	Turnover				MONEY, 
	CustomerWinLoss			MONEY, 
	WinLossShare			MONEY, 
	LicenseeComm			MONEY, 
	ShareComm				MONEY, 
	AmountDueTo				MONEY)
	
	DECLARE @CurrencyTable AS TABLE (
	CurrencyId				INT, 
	CurrencyName			VARCHAR(20), 
	CurrencyCode			VARCHAR(20))
	
	DECLARE @AllParty AS TABLE (
	PartyId					INT,
	PartyName				VARCHAR(100),
	BrandName				VARCHAR(100),
	ParentId				INT)
	
	DECLARE @SelectedParty AS TABLE (
	PartyId					INT,
	LicenseeId				INT
	)				
	
	DECLARE @VNDCurrencyName VARCHAR(20)

	SELECT @VNDCurrencyName = currency
	FROM dbo.Exchange (NOLOCK)
	WHERE ExchangeId = 51
	
	INSERT INTO @AllParty
	EXEC bodb_licensee.dbo.LA_PartyListSel
	
	INSERT INTO @SelectedParty(PartyId, LicenseeId)
	SELECT PartyID, LicenseeID
	FROM bodb_licensee.dbo.LA_f_ChargeInfo (@PartyIds, @FromDate, @ToDate, 'NG', 'OA', 1)
	GROUP BY PartyID, LicenseeID
	
	INSERT INTO @Data (SiteId, CurrencyId, WinLossDate, TotalTrans, Turnover, CustomerWinLoss, WinLossShare, LicenseeComm, ShareComm)
	SELECT sl.siteid, b.currency, b.winlostdate,
		COUNT(*) AS TotalTrans,
		SUM(b.stake) AS Turnover,
		SUM(b.winlost - b.actual_stake) AS CustomerWinLoss,
		SUM(b.actual_stake - b.winlost) * 0.03 AS WinLossShare,
		SUM(b.scomm) AS LicenseeComm,
		SUM(b.scomm * 0.03 / (1- b.tpositiontaking)) AS ShareComm
	FROM (SELECT * FROM bettrans  WITH (NOLOCK) WHERE statusID BETWEEN 111 AND 113 AND winlostdate BETWEEN @FromDate AND @ToDate) b
	INNER JOIN (SELECT matchid FROM match WITH (NOLOCK) WHERE sporttype = 44) m ON b.matchid = m.matchid
	INNER JOIN (SELECT custid, roleid, site FROM Customer WITH (NOLOCK) WHERE roleid = 2) c ON b.recommend = c.custid
	INNER JOIN Site s WITH (NOLOCK) ON c.site = s.site
	INNER JOIN (
				SELECT * 
				FROM DBLIC.bodb_Licensee.dbo.view_site_list with (nolock) 
				WHERE  siteid IN (SELECT DISTINCT sp.LicenseeId FROM @SelectedParty sp)) sl  on s.siteid = sl.IbcSiteID
	GROUP BY sl.siteid, b.currency, b.winlostdate
	
	--INSERT INTO @Data (SiteId, CurrencyId, WinLossDate, TotalTrans, Turnover, CustomerWinLoss, WinLossShare, LicenseeComm, ShareComm)
	--SELECT sl.siteid, b.currency, b.winlostdate,
	--	COUNT(*) AS TotalTrans,
	--	SUM(b.stake) AS Turnover,
	--	SUM(b.winlost - b.actual_stake) AS CustomerWinLoss,
	--	SUM(b.actual_stake - b.winlost) * 0.03 AS WinLossShare,
	--	SUM(b.scomm) AS LicenseeComm,
	--	SUM(b.scomm * 0.03 / (1- b.tpositiontaking)) AS ShareComm
	--FROM bettrans14 b WITH (NOLOCK)
	--INNER JOIN match m WITH (NOLOCK) ON b.matchid = m.matchid
	--LEFT JOIN Customer c WITH (NOLOCK) ON b.recommend = b.custid AND c.roleid = 2
	--LEFT JOIN Site s WITH (NOLOCK) ON c.site = s.siteid
	--LEFT JOIN DBLIC.bodb_Licensee.dbo.view_site_list sl with (nolock) on s.siteid = sl.IbcSiteID
	--WHERE m.sporttype = 44 
	--	  AND b.statusID BETWEEN 111 AND 113
	--	  AND b.winlostdate BETWEEN @FromDate AND @ToDate
	--GROUP BY sl.siteid, b.currency, b.winlostdate
	
	--INSERT INTO @Data (SiteId, CurrencyId, WinLossDate, TotalTrans, Turnover, CustomerWinLoss, WinLossShare, LicenseeComm, ShareComm)
	--SELECT sl.siteid, b.currency, b.winlostdate,
	--	COUNT(*) AS TotalTrans,
	--	SUM(b.stake) AS Turnover,
	--	SUM(b.winlost - b.actual_stake) AS CustomerWinLoss,
	--	SUM(b.actual_stake - b.winlost) * 0.03 AS WinLossShare,
	--	SUM(b.scomm) AS LicenseeComm,
	--	SUM(b.scomm * 0.03 / (1- b.tpositiontaking)) AS ShareComm
	--FROM DBACC.bodb_Archive.dbo.bettrans_bk b WITH (NOLOCK)
	--INNER JOIN match m WITH (NOLOCK) ON b.matchid = m.matchid
	--LEFT JOIN Customer c WITH (NOLOCK) ON b.recommend = b.custid AND c.roleid = 2
	--LEFT JOIN Site s WITH (NOLOCK) ON c.site = s.siteid
	--LEFT JOIN DBLIC.bodb_Licensee.dbo.view_site_list sl with (nolock) on s.siteid = sl.IbcSiteID
	--WHERE m.sporttype = 44 
	--	  AND b.statusID BETWEEN 111 AND 113
	--	  AND b.winlostdate BETWEEN @FromDate AND @ToDate
	--GROUP BY sl.siteid, b.currency, b.winlostdate
	
	IF((SELECT COUNT(*) FROM @Data) > 0)
	BEGIN
	
		INSERT INTO @Exchange(ExchangeId, ExchangeDate, Code, MYR, USD, EUR, CNY, GBP)
		SELECT ExchangeId, ExchangeDate, Code, MYR, USD, EUR, CNY, GBP
		FROM Lrf_f_GetExchangeDaily(@FromDate, @ToDate)
		WHERE ExchangeId IN (SELECT DISTINCT CurrencyId FROM @Data)
		
		UPDATE @Exchange
		SET Base = (CASE @BaseCurrencyName
						WHEN 'MYR' THEN MYR
						WHEN 'USD' THEN USD
						WHEN 'EUR' THEN EUR
						WHEN 'GBP' THEN GBP
						WHEN 'CNY' THEN CNY
						ELSE 1 
						END)
		
		-- Update Result
		
		INSERT INTO @Result(PartyId, PartyName, CurrencyId, WinLossDate, TotalTrans, Turnover, CustomerWinLoss, WinLossShare, LicenseeComm, ShareComm, AmountDueTo)
		SELECT  p.PartyID, p.PartyName, d.CurrencyId, d.WinLossDate,
				SUM(d.TotalTrans),
				SUM(d.Turnover * e.Base),
				SUM(d.CustomerWinLoss * e.Base),
				SUM(d.WinLossShare * e.Base),
				SUM(d.LicenseeComm * e.Base),
				SUM(d.ShareComm * e.Base),
				SUM((d.WinLossShare - d.ShareComm) * e.Base)
		FROM @Data d
		INNER JOIN (SELECT ExchangeId, ExchangeDate, Base FROM @Exchange) e ON d.CurrencyId = e.ExchangeId AND d.WinLossDate = e.ExchangeDate
		INNER JOIN @SelectedParty sp ON sp.LicenseeId = d.SiteId
		INNER JOIN (SELECT * FROM bodb_licensee..OAS_Party WHERE PartyType = 1) p ON sp.PartyId = p.PartyID  
		GROUP BY p.PartyID, p.PartyName, d.CurrencyId, d.WinLossDate
		
		INSERT INTO @CurrencyTable(CurrencyId, CurrencyName, CurrencyCode)
		SELECT t.CurrencyID, e.currency, e.Code
		FROM (SELECT DISTINCT CurrencyID FROM @Data) t
		INNER JOIN bodb02.dbo.Exchange e WITH (NOLOCK) ON t.CurrencyID = e.exchangeid
		
		UPDATE t1
		SET CurrencyCode = t1.CurrencyCode + ' (' + CurrencyName + ')'
		FROM @CurrencyTable t1
		INNER JOIN (
		   SELECT CurrencyCode
			FROM @CurrencyTable
			GROUP BY CurrencyCode
			HAVING COUNT(1) > 1
		) t2 ON t1.CurrencyCode = t2.CurrencyCode
		
		UPDATE @Result SET CurrencyName = CASE
												WHEN r.CurrencyId = 51 THEN @VNDCurrencyName
												WHEN r.CurrencyId = 20 THEN cr.CurrencyName
												ELSE cr.CurrencyCode
										  END
												
		FROM @Result r
		INNER JOIN @CurrencyTable cr ON r.CurrencyId = cr.CurrencyId
		
		Update @Result SET ParentId = p.ParentId, ParentName = p.ParentName
		FROM @Result r
		INNER JOIN (	
					SELECT ap1.PartyId,ap1.ParentId,ap2.PartyName AS ParentName
					FROM @AllParty ap1
					INNER JOIN @AllParty ap2 ON ap1.ParentId = ap2.PartyId) p ON r.PartyId = p.PartyId
				
		-- Calculate Grand Total
		INSERT INTO @GrandTotal(CurrencyName, TotalTrans, Turnover, CustomerWinLoss, WinLossShare, LicenseeComm, ShareComm, AmountDueTo)
		SELECT 'MYR', 
				SUM(d.TotalTrans), 
				SUM(d.Turnover * e.MYR), 
				SUM(d.CustomerWinLoss * e.MYR), 
				SUM(d.WinLossShare * e.MYR), 
				SUM(d.LicenseeComm * e.MYR), 
				SUM(d.ShareComm * e.MYR), 
				SUM((d.WinLossShare - d.ShareComm) * e.MYR)
		FROM @Data d
		INNER JOIN (SELECT ExchangeId, ExchangeDate, MYR FROM @Exchange) e ON d.CurrencyId = e.ExchangeId AND d.WinLossDate = e.ExchangeDate
		
		INSERT INTO @GrandTotal(CurrencyName, TotalTrans, Turnover, CustomerWinLoss, WinLossShare, LicenseeComm, ShareComm, AmountDueTo)
		SELECT 'USD', 
				SUM(d.TotalTrans), 
				SUM(d.Turnover * e.USD), 
				SUM(d.CustomerWinLoss * e.USD), 
				SUM(d.WinLossShare * e.USD), 
				SUM(d.LicenseeComm * e.USD), 
				SUM(d.ShareComm * e.USD), 
				SUM((d.WinLossShare - d.ShareComm) * e.USD)
		FROM @Data d
		INNER JOIN (SELECT ExchangeId, ExchangeDate, USD FROM @Exchange) e ON d.CurrencyId = e.ExchangeId AND d.WinLossDate = e.ExchangeDate
		
		INSERT INTO @GrandTotal(CurrencyName, TotalTrans, Turnover, CustomerWinLoss, WinLossShare, LicenseeComm, ShareComm, AmountDueTo)
		SELECT 'EUR', 
				SUM(d.TotalTrans), 
				SUM(d.Turnover * e.EUR), 
				SUM(d.CustomerWinLoss * e.EUR), 
				SUM(d.WinLossShare * e.EUR), 
				SUM(d.LicenseeComm * e.EUR), 
				SUM(d.ShareComm * e.EUR), 
				SUM((d.WinLossShare - d.ShareComm) * e.EUR)
		FROM @Data d
		INNER JOIN (SELECT ExchangeId, ExchangeDate, EUR FROM @Exchange) e ON d.CurrencyId = e.ExchangeId AND d.WinLossDate = e.ExchangeDate
		
		INSERT INTO @GrandTotal(CurrencyName, TotalTrans, Turnover, CustomerWinLoss, WinLossShare, LicenseeComm, ShareComm, AmountDueTo)
		SELECT 'GBP', 
				SUM(d.TotalTrans), 
				SUM(d.Turnover * e.GBP), 
				SUM(d.CustomerWinLoss * e.GBP), 
				SUM(d.WinLossShare * e.GBP), 
				SUM(d.LicenseeComm * e.GBP), 
				SUM(d.ShareComm * e.GBP), 
				SUM((d.WinLossShare - d.ShareComm) * e.GBP)
		FROM @Data d
		INNER JOIN (SELECT ExchangeId, ExchangeDate, GBP FROM @Exchange) e ON d.CurrencyId = e.ExchangeId AND d.WinLossDate = e.ExchangeDate
		
		INSERT INTO @GrandTotal(CurrencyName, TotalTrans, Turnover, CustomerWinLoss, WinLossShare, LicenseeComm, ShareComm, AmountDueTo)
		SELECT 'CNY', 
				SUM(d.TotalTrans), 
				SUM(d.Turnover * e.CNY), 
				SUM(d.CustomerWinLoss * e.CNY), 
				SUM(d.WinLossShare * e.CNY), 
				SUM(d.LicenseeComm * e.CNY), 
				SUM(d.ShareComm * e.CNY), 
				SUM((d.WinLossShare - d.ShareComm) * e.CNY)
		FROM @Data d
		INNER JOIN (SELECT ExchangeId, ExchangeDate, CNY FROM @Exchange) e ON d.CurrencyId = e.ExchangeId AND d.WinLossDate = e.ExchangeDate
	END
	
	SELECT * FROM @Result
	SELECT * FROM @GrandTotal
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_MuayThaiWinLoss] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_Rpt_MuayThaiWinLoss] TO bodbAdminNet 