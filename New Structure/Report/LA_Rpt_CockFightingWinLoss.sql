USE [bodb_Licensee]
GO
/****** Object:  StoredProcedure [dbo].[LA_Rpt_CockFightingWinLoss]    Script Date: 12/21/2015 06:47:11 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Rpt_CockFightingWinLoss]          
	@PartyIds			VARCHAR(500),
	@FromDate			DATETIME,
	@ToDate				DATETIME,
	@BaseCurrencyName	VARCHAR(20)
AS
/*  
	 Created: 20160225@Bravo
	 Task : Get report Cock Fighting Win Loss
	 DB: DB052.bodb_licensee
   
	 Revisions:  
	 - 20160225@Bravo: Get CF win loss data.
	 Params:			   
*/
BEGIN

	CREATE TABLE #Result (
		PartyId			INT,
		PartyName		VARCHAR(100),
		ParentId		INT,
		ParentName		VARCHAR(100),
		WinLossDate		DATETIME,
		CurrencyName	VARCHAR(20),
		TotalTrans		INT,
		Turnover		MONEY,
		CustomerWinLoss	MONEY,		
		LicenseeComm	MONEY,
		AmountDueTo		MONEY
	)

	SELECT * FROM #Result

	SELECT * FROM #Result
	
END

GO
GRANT EXECUTE ON [dbo].[LA_Rpt_CockFightingWinLoss] TO [bodbLicenseeNet] AS [dbo]
GRANT EXECUTE ON [dbo].[LA_Rpt_CockFightingWinLoss] TO [bodbAdminNet] AS [dbo]
GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_CockFightingWinLoss] TO [vnteam] AS [dbo]