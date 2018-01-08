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
		- 20171226: create SP
	Explanation:
		@IsFullyDeducted:
			0-show licensees have balance >0
			1-show licensees have balance =0
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @Parties TABLE(PartyId INT, PartyName VARCHAR(50), BrandName VARCHAR(50), ParentId INT)
	INSERT INTO @Parties (PartyId, PartyName, BrandName, ParentId)
	EXEC dbo.LA_PartyListSel @UserId = @UserId, @FunctionId=@FunctionId

	-- licensees have amf/prepayment
	-- 3-amf
	-- 22-prepayment
	DECLARE @AmfParties TABLE(PartyId INT, Balance MONEY, WaiverPeriod INT, MonthCount INT, Prepayment MONEY, Remark VARCHAR(100))
	INSERT INTO @AmfParties(PartyId, Prepayment)
	(
		SELECT p.PartyId, SUM(s.Income)
		FROM dbo.LA_InvoiceStatement s WITH(NOLOCK)
		INNER JOIN dbo.LA_InvoiceHeader h WITH(NOLOCK) on h.InvoiceHeaderId=s.InvoiceHeaderId
		INNER JOIN @Parties p ON p.PartyId = s.RefPartyId
		WHERE s.InvItemTypeId IN(3,22) AND p.ParentId > 0
			AND h.StatusId = 0 -- 0: normal invoice
			AND h.Environment=@Environment
		GROUP BY p.PartyId
	)

	-- get balance
	;WITH b AS (
		SELECT p.PartyId
			, SUM(CASE WHEN s.InvItemTypeId IN (3,5,7,21) THEN ISNULL(Income,0)-ISNULL(s.Expense,0) ELSE 0 END) AS AdvanceMinFee
			, SUM(CASE WHEN s.InvItemTypeId IN (22,23,24) THEN ISNULL(Income,0)-ISNULL(s.Expense,0) ELSE 0 END) AS Prepayment
		FROM dbo.LA_InvoiceStatement s WITH(NOLOCK)
		INNER JOIN dbo.LA_InvoiceHeader h WITH(NOLOCK) ON s.InvoiceHeaderId=h.InvoiceHeaderId
		INNER JOIN @Parties p ON p.PartyId = s.RefPartyId
		WHERE h.Environment = @Environment
			AND ISNULL(h.StatusId, 0) = 0 -- 0: normal invoice
			AND s.InvItemTypeId IN (3,5,7,21,22,23,24)
		GROUP BY p.PartyId
	)
	UPDATE af SET Balance = b.AdvanceMinFee+b.Prepayment
	FROM @AmfParties af
	INNER JOIN b ON b.PartyId = af.PartyId

	-- remark
	;WITH r AS (
		SELECT p.PartyId, s.[Description], ROW_NUMBER() OVER (PARTITION BY p.PartyId ORDER BY h.CreatedDateTime DESC) AS RowNum
		FROM dbo.LA_InvoiceStatement s WITH(NOLOCK)
		INNER JOIN dbo.LA_InvoiceHeader h WITH(NOLOCK) ON s.InvoiceHeaderId=h.InvoiceHeaderId
		INNER JOIN @Parties p ON p.PartyId = s.RefPartyId
		WHERE h.Environment = @Environment
			AND ISNULL(h.StatusId, 0) = 0 -- 0: normal invoice
			AND s.InvItemTypeId IN (3,5,21,22,23,24)-- exclude return amf-7
	)
	UPDATE af SET Remark = r.[Description]
	FROM @AmfParties af
	INNER JOIN r ON r.PartyId = af.PartyId AND r.RowNum = 1

	-- launching date
	-- 1-party
	-- 5-un-official party
	DECLARE @LaunchingDate TABLE(LaunchindDate DATE, PartyId INT, PartyType INT)
	;WITH P AS (
		SELECT ci.FromDate, p.PartyID, p.PartyType
		FROM dbo.OAS_Party p WITH (NOLOCK)
			INNER JOIN dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
			INNER JOIN dbo.LA_ChargeInfo_SystemMapping map WITH(NOLOCK) ON map.ChargeID = ci.ChargeID and map.SystemID = 2
		WHERE ci.ProductId NOT IN (SELECT DISTINCT ProductId FROM dbo.LA_Product3rdSub WITH(NOLOCK)) AND p.PartyType IN (1,5)
		UNION ALL
		SELECT s.FromDate, p.PartyID, p.PartyType
		FROM dbo.OAS_Party p WITH (NOLOCK)
			INNER JOIN dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
			INNER JOIN dbo.LA_ChargeInfo_SystemMapping map WITH(NOLOCK) ON map.ChargeID = ci.ChargeID and map.SystemID = 2
			INNER JOIN dbo.OAS_ChargeInfoSub s WITH (NOLOCK) ON s.ChargeIDRef = ci.ChargeID AND s.FromParty = ci.FromParty
		WHERE p.PartyType IN (1,5)
	)
	INSERT INTO @LaunchingDate(LaunchindDate, PartyId, PartyType)
	SELECT MIN(FromDate), PartyID, PartyType FROM P GROUP BY PartyID, PartyType

	-- waiver period
	-- 1 minfee
	-- 2 waive
	;WITH wp AS (
		SELECT w.PartyId, SUM(DATEDIFF(MONTH,w.FromDate,w.ToDate )+1) WaiverPeriod
		FROM dbo.LA_MinFee w WITH(NOLOCK)
		INNER JOIN dbo.LA_MinFee m WITH(NOLOCK) ON m.PartyId=w.PartyId AND m.ProductId=w.ProductId
		WHERE w.FeeTypeId = 2 AND m.FeeTypeId=1 AND w.FromDate >= m.FromDate AND w.ToDate<=m.ToDate
		GROUP BY w.PartyId
	)
	UPDATE p SET p.WaiverPeriod = ISNULL(wp.WaiverPeriod, 0)
	FROM @AmfParties p
	LEFT JOIN wp ON wp.PartyId=p.PartyId

	SELECT REPLACE(pp.PartyName, ' Licensees', '') AS GroupName
		, p.PartyId
		, p.PartyName
		, af.Prepayment
		, l.LaunchindDate
		, af.WaiverPeriod
		, ISNULL(af.MonthCount,0) AS MonthCount
		, af.Balance
		, ISNULL(af.Remark,'') AS Remark
		, l.PartyType
	FROM @AmfParties af
	INNER JOIN @Parties p ON af.PartyId=p.PartyId AND p.ParentId>0
	INNER JOIN @LaunchingDate l ON l.PartyId=p.PartyId
	INNER JOIN @Parties pp ON pp.PartyId=p.ParentId AND pp.ParentId=0

	-- get deduct amount detail
	-- 5-deduct AMF
	-- 24-deduct against invoice
	DECLARE @Deduct TABLE(PartyId INT, InvoiceNo VARCHAR(50), Amount MONEY)
	INSERT INTO @Deduct(PartyId, InvoiceNo, Amount)
	(
		SELECT p.PartyId, h.OfficialInvoiceNo, SUM(s.Expense) AS Amount
		FROM dbo.LA_InvoiceStatement s
		INNER JOIN dbo.LA_InvoiceHeader h on h.InvoiceHeaderId=s.InvoiceHeaderId
		INNER JOIN @AmfParties p ON p.PartyId = s.RefPartyId
		WHERE s.InvItemTypeId IN(5,24)
			AND h.StatusId = 0 -- 0: normal invoice
			AND h.Environment=@Environment
		GROUP BY p.PartyId, h.OfficialInvoiceNo
	)

	;WITH r AS (
		SELECT p.PartyId,s.RefNo,SUM(s.Income) AS Amount
		FROM dbo.LA_InvoiceStatement s
		INNER JOIN dbo.LA_InvoiceHeader h on h.InvoiceHeaderId=s.InvoiceHeaderId
		INNER JOIN @AmfParties p ON p.PartyId = s.RefPartyId
		WHERE s.InvItemTypeId = 7-- 7-return amf
			AND h.StatusId = 0 -- 0: normal invoice
			AND h.Environment=@Environment
		GROUP BY p.PartyId,s.RefNo
	)
	SELECT d.PartyId, d.InvoiceNo, d.Amount - ISNULL(r.Amount,0) AS Amount
	FROM @Deduct d
	LEFT JOIN r ON d.InvoiceNo = r.RefNo
	ORDER BY d.PartyId, d.InvoiceNo
END
GO

GRANT EXECUTE ON [dbo].[LA_Rpt_AmfSummary] TO bodbAdminNet
GO
