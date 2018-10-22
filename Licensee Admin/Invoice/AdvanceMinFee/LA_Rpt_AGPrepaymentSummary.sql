/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/

USE [bodb_Licensee]
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].[LA_Rpt_AGPrepaymentSummary]
	@Environment		VARCHAR(50),
	@UserId				INT,
	@FunctionId			INT
AS
/*	Header:
	Created: 20181003 - Parsons
	Task : Get AG Casino Prepayment Summary
	DB: DB052.bodb_Licensee

	Revisions:
		- 20181003@Parsons: Integrate AG setup fee into invoices [RedmineID: #98485]
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @AGP INT = 25, @DeductAGP INT = 26

	DECLARE @Parties TABLE(PartyId INT, PartyName VARCHAR(50), BrandName VARCHAR(50), ParentId INT)
	INSERT INTO @Parties (PartyId, PartyName, BrandName, ParentId)
	EXEC dbo.LA_PartyListSel @UserId = @UserId, @FunctionId=@FunctionId

	INSERT INTO @Parties (PartyId, PartyName, BrandName, ParentId)
	EXEC dbo.LA_PartyListNonOfficialSel

	-- Step 1: Get all invoiceStatement which has invItemTypeId in (25, 26)
	DECLARE @AGPSummary TABLE(
		ParentId	INT,
		ParentName	VARCHAR(50),
		PartyId		INT,
		PartyName	VARCHAR(50),
		Amount		MONEY,
		InvoiceNo	VARCHAR(50),
		InvItemTypeId	INT
	)
	INSERT INTO @AGPSummary(ParentId, PartyId, PartyName, InvoiceNo, InvItemTypeId, Amount)
	(
		SELECT p.ParentId, p.PartyId, p.PartyName, h.OfficialInvoiceNo, s.InvItemTypeId, SUM(CASE WHEN s.InvItemTypeId = @AGP THEN ISNULL(s.Income, 0) ELSE ISNULL(s.Expense, 0)END)
		FROM dbo.LA_InvoiceStatement s WITH(NOLOCK)
		INNER JOIN dbo.LA_InvoiceHeader h WITH(NOLOCK) on h.InvoiceHeaderId=s.InvoiceHeaderId
		INNER JOIN @Parties p ON p.PartyId = s.RefPartyId
		WHERE s.InvItemTypeId IN(@AGP,@DeductAGP) AND p.ParentId > 0
			AND h.StatusId = 0 -- 0: normal invoice
			AND h.Environment=@Environment
		GROUP BY p.ParentId, p.PartyId, p.PartyName, h.OfficialInvoiceNo, s.InvItemTypeId
	)

	-- Select summary
	;WITH cte_agpSummary AS (
		SELECT  ParentId,
				PartyId,
				PartyName,
				SUM(CASE WHEN InvItemTypeId = @AGP THEN Amount ELSE 0 END) AS Prepayment,
				SUM(CASE WHEN InvItemTypeId = @DeductAGP THEN Amount ELSE 0 END) AS TotalMonthlyFee
		FROM @AGPSummary
		GROUP BY ParentId, PartyId, PartyName
	)
	SELECT  REPLACE(p.PartyName, ' Licensees', '') AS GroupName,
			a.PartyId,
			a.PartyName,
			a.Prepayment,
			(a.Prepayment - a.TotalMonthlyFee) AS Balance
	FROM cte_agpSummary a 
	INNER JOIN @Parties p ON a.ParentId = p.PartyId

	-- Select invoice items
	SELECT  a.PartyId,
			InvoiceNo,
			Amount
			
	FROM @AGPSummary a
	WHERE a.InvItemTypeId = @DeductAGP
	ORDER BY InvoiceNo 
END
GO