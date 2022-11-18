/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_AmfSummary]
	@Environment		VARCHAR(50),
	@UserId				INT,
	@FunctionKey		NVARCHAR(100)
AS
/*	Header:
	Created: 20171226 - Bruce.Bui
	Task : Manage AMF
	DB: DBCUST.bodb_Licensee

	Revisions:
		- 20171226@Bruce: create SP report for AMF Summary [RedmineID: #87039]
		- 20180326@Harper: Change the way to get Waive month [RedmineID: #87039]
		- 20180716@bruce: add new group TEST for credit [#98126]
		- 20190821@Parsons: Improve the ability to maintain systems [#118627]
		- 20220418@Percy: Add Credit note for AMF [RedmineID: #164139]
		- 20221109@Malcolm: add LicenseeCode, BaseCurrencyId [RedmineID : 175860]
*/
BEGIN
	SET NOCOUNT ON

	-- Get Party List
	BEGIN
		DECLARE @PartyList TABLE (PartyId INT, PartyName VARCHAR(50), BrandName VARCHAR(50), ParentId INT, LicenseeCode VARCHAR(50), BaseCurrencyId TINYINT)

		-- Official Licensees
		INSERT INTO @PartyList (PartyId, PartyName, BrandName, ParentId)
		EXEC dbo.LA_PartyListSel @UserId = @UserId, @FunctionKey = @FunctionKey

		-- Non-Official Licensees
		INSERT INTO @PartyList (PartyId, PartyName, BrandName, ParentId, LicenseeCode, BaseCurrencyId)
		EXEC dbo.LA_PartyListNonOfficialSel
	END

	-- Get AMF, Prepayment & Credit note for Fees
	BEGIN
		CREATE TABLE #tmpData (PartyId INT, InvoiceType SMALLINT, OfficialInvoiceNo NVARCHAR(50), CreatedDateTime DATETIME, RefNo NVARCHAR(50)
			,RefInvItemTypeId SMALLINT, InvItemTypeId SMALLINT, Amount MONEY, Description NVARCHAR(500))

		INSERT INTO #tmpData (PartyId, InvoiceType, OfficialInvoiceNo,CreatedDateTime, RefNo, InvItemTypeId, Amount, Description, RefInvItemTypeId)
		SELECT s.RefPartyId, h.InvoiceType, h.OfficialInvoiceNo, h.CreatedDateTime, s.RefNo, s.InvItemTypeId, ISNULL(s.Income, 0) - ISNULL(s.Expense, 0), s.Description
			,CASE
				WHEN InvItemTypeId IN (3, 5, 7, 21, 46) THEN 3 -- AMF
				WHEN InvItemTypeId IN (22, 23, 24) THEN 22 -- Prepayment
				END AS RefInvItemTypeId
		FROM dbo.LA_InvoiceHeader h WITH (NOLOCK)
			INNER JOIN dbo.LA_InvoiceStatement s WITH (NOLOCK) ON s.InvoiceHeaderId = h.InvoiceHeaderId
		WHERE h.StatusId = 0 -- normal invoice
			AND h.Environment = @Environment
			AND s.InvItemTypeId IN (
				3, 5, 7, 21, 46 -- AMF
				,22, 23, 24 -- Prepayment
			)

		-- Remove invalid data
		DELETE t
		FROM #tmpData t
			LEFT JOIN @PartyList pl ON t.PartyId = pl.PartyId AND pl.ParentId <> 0
		WHERE pl.PartyId IS NULL

		DELETE t
		FROM #tmpData t
			INNER JOIN (
				SELECT PartyId, RefInvItemTypeId
				FROM #tmpData
				GROUP BY PartyId, RefInvItemTypeId
				HAVING MIN(InvItemTypeId) <> RefInvItemTypeId
			) w ON t.PartyId = w.PartyId AND t.RefInvItemTypeId = w.RefInvItemTypeId
	END

	CREATE TABLE #Result (PartyId INT, PartyName VARCHAR(50), ParentId INT, ParentName VARCHAR(50), PartyType TINYINT, LaunchingDate DATE, WaiverPeriod INT, MonthCount INT, RefInvItemTypeId SMALLINT, InitAmount MONEY, Balance MONEY, Remark NVARCHAR(500))

	INSERT INTO #Result (PartyId, RefInvItemTypeId, InitAmount, Balance)
	SELECT t.PartyId, t.RefInvItemTypeId, SUM(CASE WHEN t.InvItemTypeId IN (3, 22) THEN t.Amount ELSE 0 END) AS InitAmount, SUM(t.Amount) AS Balance
	FROM #tmpData t
	GROUP BY t.PartyId, t.RefInvItemTypeId

	-- #Result: Update Remark
	UPDATE r
	SET r.Remark = t.Remark
	FROM #Result r
		INNER JOIN (
			SELECT t1.PartyId, t1.RefInvItemTypeId, CASE WHEN t1.InvoiceType = 7 THEN N'' ELSE t1.Description END AS Remark
				,ROW_NUMBER() OVER (PARTITION BY t1.PartyId, t1.RefInvItemTypeId ORDER BY t1.CreatedDateTime DESC) AS RowNum
			FROM #tmpData t1
				LEFT JOIN #tmpData t2 ON t1.OfficialInvoiceNo = t2.RefNo AND t2.InvItemTypeId = 7 -- Setup Fees
			WHERE t1.InvItemTypeId IN (3, 21, 22, 23) AND t2.RefNo IS NULL
		) t ON r.PartyId = t.PartyId AND r.RefInvItemTypeId = t.RefInvItemTypeId
	WHERE t.RowNum = 1

	-- #Result: Update Party Info
	UPDATE r
	SET r.PartyName = pl.PartyName, r.ParentId = pl.ParentId, r.ParentName = REPLACE(pr.PartyName, ' Licensees', ''), r.PartyType = p.PartyType, r.LaunchingDate = c.LaunchingDate
	FROM #Result r
		INNER JOIN @PartyList pl ON r.PartyId = pl.PartyId
		INNER JOIN @PartyList pr ON pl.ParentId = pr.PartyId
		INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON r.PartyId = p.PartyId
		OUTER APPLY (
			SELECT MIN(c.FromDate) AS LaunchingDate
			FROM dbo.OAS_ChargeInfo c WITH (NOLOCK)
			WHERE c.FromParty = r.PartyId
				AND c.ToParty IN (1, 9, 11, 98)
				AND c.ChargeType NOT IN (2, 3) -- old type
		) c

	-- #Result: Update Waiver period
	UPDATE r
	SET r.WaiverPeriod = w.WaiverPeriod, r.MonthCount = 0
	FROM #Result r
		CROSS APPLY (
			SELECT SUM(DATEDIFF(MONTH, w.FromDate, DATEADD(DAY, 1, w.ToDate)) + CASE WHEN DAY(w.FromDate) > DAY(DATEADD(DAY, 1, w.ToDate)) THEN -1 ELSE 0 END) AS WaiverPeriod
			FROM dbo.LA_MinFee m WITH (NOLOCK)
				INNER JOIN dbo.LA_MinFee w WITH (NOLOCK) ON m.PartyId = w.PartyId AND m.ProductId = w.ProductId
			WHERE m.PartyId = r.PartyId AND m.FeeTypeId = 1 AND w.FeeTypeId = 2 AND w.FromDate >= m.FromDate AND w.ToDate <= m.ToDate
		) w
	WHERE r.RefInvItemTypeId = 3

	-- #Result: Update MonthCount
	UPDATE r
	SET r.MonthCount = MonthOfDeduction
	FROM #Result r
		CROSS APPLY (
			SELECT TOP 1 m.MonthOfDeduction
			FROM dbo.LA_MinFee m WITH (NOLOCK)
			WHERE m.PartyId = r.PartyId AND m.FeeTypeId = 1
			ORDER BY m.ToDate DESC
		) w
	WHERE r.RefInvItemTypeId = 3
	
	-- Return data
	SELECT ParentName AS GroupName, PartyId, PartyName, InitAmount AS Prepayment, LaunchingDate, ISNULL(WaiverPeriod, 0) AS WaiverPeriod, ISNULL(MonthCount, 0) AS MonthCount
		,Balance, ISNULL(Remark, '') AS Remark, ISNULL(PartyType, 5) AS PartyType, RefInvItemTypeId AS RowType
	FROM #Result
	ORDER BY PartyId, RefInvItemTypeId

	-- Deducted amount detail
	SELECT d.PartyId, d.RefNo AS InvoiceNo, d.Amount - ISNULL(t.Amount, 0) AS Amount, d.RefInvItemTypeId AS RowType
	FROM (
		SELECT PartyId, RefInvItemTypeId, CASE WHEN InvoiceType = 10 THEN RefNo ELSE OfficialInvoiceNo END AS RefNo, -SUM(Amount) AS Amount
		FROM #tmpData t1
		WHERE InvItemTypeId IN (5, 24, 46) -- Deducted amount
		GROUP BY PartyId, RefInvItemTypeId, CASE WHEN InvoiceType = 10 THEN RefNo ELSE OfficialInvoiceNo END
	) d
		LEFT JOIN (
			SELECT PartyId, RefNo, SUM(Amount) AS Amount
			FROM #tmpData
			WHERE InvItemTypeId = 7
			GROUP BY PartyId, RefNo
		) t ON d.PartyId = d.PartyId AND d.RefNo = t.RefNo AND d.RefInvItemTypeId = 3
	WHERE d.Amount - ISNULL(t.Amount, 0) <> 0
	ORDER BY d.PartyId, d.RefNo, d.RefInvItemTypeId

	DROP TABLE #Result
	DROP TABLE #tmpData
END
GO