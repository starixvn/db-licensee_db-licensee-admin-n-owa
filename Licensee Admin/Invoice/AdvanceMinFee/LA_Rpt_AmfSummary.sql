/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/

USE [bodb_Licensee]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_AmfSummary]
	@Environment		VARCHAR(50),
	@UserId				INT,
	@FunctionId			INT
AS
/*	Header:
	Created: 20171226 - Bruce.Bui
	Task : Manage AMF
	DB: DB052.bodb_Licensee

	Revisions:
		- 20171226@Bruce: create SP report for AMF Summary [RedmineID: #87039]
		- 20180326@Harper: Change the way to get Waive month [RedmineID: #87039]
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @AMF INT = 3
	DECLARE @PREPAYMENT INT = 22

	DECLARE @Parties TABLE(PartyId INT, PartyName VARCHAR(50), BrandName VARCHAR(50), ParentId INT)
	INSERT INTO @Parties (PartyId, PartyName, BrandName, ParentId)
	EXEC dbo.LA_PartyListSel @UserId = @UserId, @FunctionId=@FunctionId
	
	INSERT INTO @Parties (PartyId, PartyName, BrandName, ParentId)
	EXEC dbo.LA_PartyListNonOfficialSel

	-- licensees have amf/prepayment
	-- 3-amf
	-- 22-prepayment
	DECLARE @AmfParties TABLE(
		PartyId INT,
		Balance MONEY,
		WaiverPeriod INT,
		MonthCount INT,
		InitialAmount MONEY,
		Remark VARCHAR(100),
		PartyName VARCHAR(50),
		ParentId INT,
		RowType INT
	)
	INSERT INTO @AmfParties(PartyId, InitialAmount, PartyName, ParentId, RowType)
	(
		SELECT p.PartyId, SUM(s.Income), p.PartyName, p.ParentId,s.InvItemTypeId
		FROM dbo.LA_InvoiceStatement s WITH(NOLOCK)
		INNER JOIN dbo.LA_InvoiceHeader h WITH(NOLOCK) on h.InvoiceHeaderId=s.InvoiceHeaderId
		INNER JOIN @Parties p ON p.PartyId = s.RefPartyId
		WHERE s.InvItemTypeId IN(@AMF,@PREPAYMENT) AND p.ParentId > 0
			AND h.StatusId = 0 -- 0: normal invoice
			AND h.Environment=@Environment
		GROUP BY p.PartyId, p.PartyName, p.ParentId,s.InvItemTypeId
	)

	-- statement
	-- 3,5,7,21: amf
	-- 22: prepayment
	SELECT s.[Description],s.Expense,s.Income,s.InvItemTypeId,s.RefNo,s.RefPartyId, h.CreatedDateTime, h.OfficialInvoiceNo, h.InvoiceType,
		CASE WHEN s.InvItemTypeId IN (3,5,7,21) THEN @AMF ELSE @PREPAYMENT END RowType
	INTO #Statement
	FROM dbo.LA_InvoiceStatement s WITH(NOLOCK)
	INNER JOIN dbo.LA_InvoiceHeader h WITH(NOLOCK) ON s.InvoiceHeaderId=h.InvoiceHeaderId
	WHERE h.Environment = @Environment
		AND ISNULL(h.StatusId, 0) = 0 -- 0: normal invoice
		AND s.InvItemTypeId IN (3,5,7,21,22,23,24)
		AND s.RefPartyId IN (SELECT a.PartyId FROM @AmfParties a)

	-- get balance
	;WITH b AS (
		SELECT RefPartyId, RowType, SUM(ISNULL(Income,0)-ISNULL(Expense,0)) AS Balance
		FROM #Statement
		GROUP BY RefPartyId, RowType
	)
	UPDATE af SET Balance = b.Balance
	FROM @AmfParties af
	INNER JOIN b ON b.RefPartyId = af.PartyId AND b.RowType=af.RowType

	-- remark
	-- invoice type: 7-setupfee
	-- item type: 3,21,22,23
	;WITH r AS (
		SELECT s1.RefPartyId, s1.RowType
			, CASE WHEN s1.InvoiceType=7 THEN '' ELSE s1.[Description] END AS [Description]
			, ROW_NUMBER() OVER (PARTITION BY s1.RefPartyId,s1.RowType ORDER BY s1.CreatedDateTime DESC) AS RowNum
		FROM #Statement s1
		LEFT JOIN #Statement s2 ON s1.OfficialInvoiceNo=s2.RefNo AND s2.InvItemTypeId = 7
		WHERE s1.InvItemTypeId IN(3,21,22,23) AND s2.RefNo IS NULL
	)
	UPDATE af SET Remark = r.[Description]
	FROM @AmfParties af
	INNER JOIN r ON r.RefPartyId = af.PartyId AND r.RowType=af.RowType AND r.RowNum = 1

	-- launching date
	-- 1-party
	-- 5-un-official party
	DECLARE @LaunchingDate TABLE(LaunchingDate DATE, PartyId INT, PartyType INT)
	;WITH P AS (
		SELECT ci.FromDate, p.PartyID, p.PartyType
		FROM dbo.OAS_Party p WITH (NOLOCK)
		INNER JOIN @AmfParties af ON af.PartyId=p.PartyID
		INNER JOIN dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
		INNER JOIN dbo.LA_ChargeInfo_SystemMapping map WITH(NOLOCK) ON map.ChargeID = ci.ChargeID and map.SystemID = 2
		WHERE ci.ProductId NOT IN (SELECT DISTINCT ProductId FROM dbo.LA_Product3rdSub WITH(NOLOCK)) AND p.PartyType IN (1,5)
		UNION ALL
		SELECT s.FromDate, p.PartyID, p.PartyType
		FROM dbo.OAS_Party p WITH (NOLOCK)
		INNER JOIN @AmfParties af ON af.PartyId=p.PartyID
		INNER JOIN dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
		INNER JOIN dbo.LA_ChargeInfo_SystemMapping map WITH(NOLOCK) ON map.ChargeID = ci.ChargeID and map.SystemID = 2
		INNER JOIN dbo.OAS_ChargeInfoSub s WITH (NOLOCK) ON s.ChargeIDRef = ci.ChargeID AND s.FromParty = ci.FromParty
		WHERE p.PartyType IN (1,5)
	)
	INSERT INTO @LaunchingDate(LaunchingDate, PartyId, PartyType)
	SELECT MIN(FromDate), PartyID, PartyType FROM P GROUP BY PartyID, PartyType

	-- waiver period
	-- 1 minfee
	-- 2 waive
	-- 3 amf
	;WITH wp AS (
		SELECT w.PartyId, w.FromDate, DATEADD(DAY, 1, w.ToDate) AS ToDate
		FROM dbo.LA_MinFee w WITH(NOLOCK)
		INNER JOIN dbo.LA_MinFee m WITH(NOLOCK) ON m.PartyId=w.PartyId AND m.ProductId=w.ProductId
		INNER JOIN @AmfParties af ON af.PartyId=w.PartyId AND af.RowType=@AMF
		WHERE w.FeeTypeId = 2 AND m.FeeTypeId=1 AND w.FromDate >= m.FromDate AND w.ToDate<=m.ToDate		
	)
	, waive AS (
		SELECT wp.PartyId,
				SUM(    CASE
						WHEN DATEADD(Month, DATEDIFF(Month, wp.FromDate, wp.ToDate) +1, wp.FromDate) <= wp.ToDate Then DATEDIFF(Month, wp.FromDate, wp.ToDate) +1
						WHEN DATEADD(Month, DATEDIFF(Month, wp.FromDate, wp.ToDate) , wp.FromDate) <= wp.ToDate Then DATEDIFF(Month, wp.FromDate, wp.ToDate) 
						WHEN DATEADD(Month, DATEDIFF(Month, wp.FromDate, wp.ToDate) -1, wp.FromDate) <= wp.ToDate Then DATEDIFF(Month, wp.FromDate, wp.ToDate) -1
						END ) WaiverPeriod
		FROM wp
		GROUP BY wp.PartyId
	)
	UPDATE p SET p.WaiverPeriod = ISNULL(waive.WaiverPeriod, 0)
	FROM @AmfParties p
	LEFT JOIN waive ON waive.PartyId=p.PartyId
	WHERE p.RowType=@AMF

	-- month of deduction
	-- 1 minfee
	;WITH md AS (
		SELECT m.PartyId, m.MonthOfDeduction, ROW_NUMBER() OVER (PARTITION BY m.PartyId ORDER BY m.ToDate DESC) AS RowNum
		FROM dbo.LA_MinFee m WITH(NOLOCK)
		INNER JOIN @AmfParties p ON p.PartyId = m.PartyId AND p.RowType=@AMF
		WHERE m.FeeTypeId=1
	)
	UPDATE p SET p.MonthCount = md.MonthOfDeduction
	FROM @AmfParties p
	INNER JOIN md ON p.PartyId=md.PartyId AND md.RowNum=1
	WHERE p.RowType=@AMF

	SELECT REPLACE(pp.PartyName, ' Licensees', '') AS GroupName
		, af.PartyId
		, af.PartyName
		, af.InitialAmount				AS Prepayment
		, l.LaunchingDate
		, ISNULL(af.WaiverPeriod,0)		AS WaiverPeriod
		, ISNULL(af.MonthCount,0)		AS MonthCount
		, af.Balance
		, ISNULL(af.Remark,'')			AS Remark
		, ISNULL(l.PartyType,5)			AS PartyType-- un-official party
		, af.RowType
	FROM @AmfParties af
	LEFT JOIN @LaunchingDate l ON l.PartyId=af.PartyId
	INNER JOIN @Parties pp ON pp.PartyId=af.ParentId AND pp.ParentId=0

	-- get deduct amount detail
	-- 5-deduct AMF
	-- 24-deduct against invoice
	DECLARE @Deduct TABLE(PartyId INT, InvoiceNo VARCHAR(50), Amount MONEY, RowType INT)
	INSERT INTO @Deduct(PartyId, RowType, Amount, InvoiceNo)
	(
		SELECT RefPartyId, InvItemTypeId,
			SUM(ISNULL(Expense,0)) AS Amount,
			CASE WHEN InvoiceType = 10 THEN RefNo ELSE OfficialInvoiceNo END
		FROM #Statement
		WHERE InvItemTypeId IN (5,24) --Debit Note (for return AMF)
		GROUP BY RefPartyId,InvItemTypeId, CASE WHEN InvoiceType = 10 THEN RefNo ELSE OfficialInvoiceNo END
	)

	--10   Debit Note (for return AMF)
	--7    Return amf
	--24   Deduct against invoice
	;WITH r AS (
		SELECT RefPartyId,RefNo, SUM(ISNULL(Income,0)) AS Amount
		FROM #Statement
		WHERE InvItemTypeId = 7
		GROUP BY RefPartyId,RefNo
	)
	SELECT d.PartyId, d.InvoiceNo
		, (d.Amount - ISNULL(r.Amount,0)) AS Amount
		, CASE WHEN d.RowType=5 THEN @AMF ELSE @PREPAYMENT END AS RowType
	FROM @Deduct d
	LEFT JOIN r ON d.InvoiceNo = r.RefNo AND d.RowType = 5 --deduct AMF
	WHERE (d.Amount - ISNULL(r.Amount,0)) <> 0
	ORDER BY d.PartyId, d.InvoiceNo

	DROP TABLE #Statement
END
GO

GRANT EXECUTE ON [dbo].[LA_Rpt_AmfSummary] TO bodbAdminNet
GO
