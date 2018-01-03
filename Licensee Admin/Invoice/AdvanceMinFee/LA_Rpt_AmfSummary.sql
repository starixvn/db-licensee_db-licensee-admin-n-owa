/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/

USE [bodb_Licensee]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_AmfSummary]
	@IsFullyDeducted	BIT,
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
	DECLARE @PaidParties TABLE(PartyId INT, Balance MONEY, LaunchingDate DATETIME, WaiverPeriod INT, MonthCount INT, Prepayment MONEY)
	INSERT INTO @PaidParties(PartyId, Prepayment)
	(
		SELECT p.PartyId, SUM(s.Income)
		FROM dbo.LA_InvoiceStatement s
		INNER JOIN dbo.LA_InvoiceHeader h on h.InvoiceHeaderId=s.InvoiceHeaderId
		INNER JOIN @Parties p ON p.PartyId = s.RefPartyId
		WHERE s.InvItemTypeId IN(3,22) AND p.ParentId > 0
			AND h.StatusId = 0 -- 0: normal invoice
			AND h.Environment=@Environment
		GROUP BY p.PartyId
	)

	-- get deduct amount detail
	-- 5-deduct AMF
	-- 24-deduct against invoice
	DECLARE @InvoiceList TABLE(PartyId INT,InvoiceNo VARCHAR(50), Amount MONEY)
	;WITH d AS (
		SELECT p.PartyId, h.OfficialInvoiceNo, SUM(s.Expense) AS Amount
		FROM dbo.LA_InvoiceStatement s
		INNER JOIN dbo.LA_InvoiceHeader h on h.InvoiceHeaderId=s.InvoiceHeaderId
		INNER JOIN @PaidParties p ON p.PartyId = s.RefPartyId
		WHERE s.InvItemTypeId IN(5,24)
			AND h.StatusId = 0 -- 0: normal invoice
			AND h.Environment=@Environment
	)
	SELECT d.Amount - SUM(ISNULL(s.Income,0)), d.PartyId, d.OfficialInvoiceNo
	FROM dbo.LA_InvoiceStatement s
	INNER JOIN dbo.LA_InvoiceHeader h on h.InvoiceHeaderId=s.InvoiceHeaderId
	INNER JOIN @PaidParties p ON p.PartyId = s.RefPartyId
	RIGHT JOIN d ON d.OfficialInvoiceNo=s.RefNo
	WHERE s.InvItemTypeId = 7-- 7-return amf
		AND h.StatusId = 0 -- 0: normal invoice
		AND h.Environment=@Environment
	GROUP BY d.Amount, d.PartyId, d.OfficialInvoiceNo

		SELECT p.PartyId, p.PartyName, p.BrandName, p.ParentId
			, SUM(CASE WHEN s.InvItemTypeId IN (3,5,7,21) THEN ISNULL(Income,0)-ISNULL(s.Expense,0) ELSE 0 END) AS AdvanceMinFee
			, SUM(CASE WHEN s.InvItemTypeId IN (22,23,24) THEN ISNULL(Income,0)-ISNULL(s.Expense,0) ELSE 0 END) AS Prepayment
		FROM dbo.LA_InvoiceStatement s WITH(NOLOCK)
		INNER JOIN dbo.LA_InvoiceHeader h WITH(NOLOCK) ON s.InvoiceHeaderId=h.InvoiceHeaderId
		INNER JOIN @Parties p ON p.PartyId = s.RefPartyId
		WHERE h.Environment = @Environment
			AND ISNULL(h.StatusId, 0) = 0 -- 0: normal invoice
			AND s.InvItemTypeId IN (3,5,7,21,22,23,24)
		GROUP BY p.PartyId, p.PartyName, p.BrandName, p.ParentId
END
GO

GRANT EXECUTE ON [dbo].[LA_Rpt_AmfSummary] TO bodbAdminNet
GO
