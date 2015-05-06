USE [bodb02]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[LA_Rpt_ThirdPartyProductWinloss] 
	@ProductCodes		VARCHAR(100)	
	, @Recommend		VARCHAR(8000)	= ''
	, @Currency 		INT 			= 0
	, @DrawFilter		TINYINT			= 1
	, @FromDate 		SMALLDATETIME
	, @ToDate 			SMALLDATETIME	
AS
/*  
    Created: Florent.Nguyen
    Date: 2015-03-26
    Task : Get product winloss of third party
    DB: DBEXT.bodb02  
    Revisions:  		

	Param's Explanation:  
		@DrawFilter :	1 Normal
						2 No Draw
						3 No Draw for Turnonver only
*/
SET NOCOUNT ON

BEGIN	
	DECLARE @TempAG AS TABLE (CustID INT)	
	DECLARE @GetAll BIT = 1

	IF ISNULL(@Recommend, '') <> ''
	BEGIN
		INSERT INTO @TempAG (CustID)
		SELECT val 
		FROM dbo.strSplit(@Recommend, ',')

		SET @GetAll = 0
	END

	SELECT co.recommend			AS Recommend	
		, c.Winlostdate			AS rptDate
		, c.Currency			AS CurrencyId
		, SUM(c.TurnOver - 
				CASE WHEN @DrawFilter IN (2, 3) 
						THEN c.DrawTO 
					ELSE 0 
				END)			AS TurnOver
		, SUM(c.BetCount - 
				CASE WHEN @DrawFilter = 2
								THEN c.DrawBetCount
							ELSE 0 
						END)	AS TotalTrans
		, SUM(c.Winlost)		AS Winloss
	FROM bodb_LicenseeReport.dbo.rptDepWinlost_ThirdParty c WITH (NOLOCK)
		INNER JOIN dbo.Custinfo co WITH (NOLOCK) ON c.CustID = co.CustID	
	WHERE c.Winlostdate BETWEEN @FromDate AND @Todate
		AND (@GetAll = 1 OR (@GetAll = 0 AND co.recommend IN (SELECT CustID FROM @TempAG)))
		AND (c.ProductId IN ( SELECT ProductID FROM bodb_licensee.dbo.LRF_f_Products3rd(@ProductCodes)))
	GROUP BY co.recommend, c.Winlostdate, c.Currency		
END

GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_ThirdPartyProductWinloss] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_Rpt_ThirdPartyProductWinloss] TO bodbAdminNet