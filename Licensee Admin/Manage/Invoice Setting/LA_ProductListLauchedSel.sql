/*<info serverAlias="DBCUST-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_ProductListLauchedSel]
	@PayerId	INT	= 0	
AS
/*  
	Created: 20170224@scofield.huynh
	Task : get All Launched Products
	DB: DBCUST.bodb_Licensee  
   
	Revisions:     	
		- 20170301@Scofield: Update to exclude 'RB', 'BG', 'PTCS', 'HF' and inclucde 'SB' [#70050]
		- 20210812@Percy: Exclude BitCoin from Product drop-down list [RedmineID: #159691]
		- 20211026@Danny: Treat SLT as a part of SB based on cutoff date [RedmineID: #163181]
		- 20240306@Danny: Merge virtual sports product [RemineID: #199478]
	
	Example:
		EXEC dbo.LA_ProductListLauchedSel
*/
BEGIN
	SET NOCOUNT ON

	SELECT p.ProductID, p.ProductCode  ProductPrefix, p.ProductName
	FROM dbo.LA_f_GroupProduct('',NULL,NULL) p
	WHERE p.ProductId NOT IN (1, 7, 9, 16, 27, 49, 77, 83) -- RB, BG, PTCS, HF, VS2, VS3, LG, VS4
		AND (
			p.ProductId = 0 -- always SB
			OR EXISTS (
				SELECT 1
				FROM dbo.OAS_Party op WITH (NOLOCK)
					INNER JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON op.PartyId = pd.PartyId
					LEFT JOIN dbo.Labels l WITH (NOLOCK) ON op.OldRefId = l.LicenseeId
					INNER JOIN dbo.LicenseeProduct3rd lp WITH (NOLOCK) ON lp.LicenseeId = CASE WHEN pd.IsDeposit = 0 THEN l.LabelId ELSE op.OldRefId END
				WHERE lp.ProductId = p.ProductId AND op.PartyID = @PayerId
			)
		)
		AND p.ProductId = p.GroupProductId
END
GO