set ANSI_NULLS ON
set QUOTED_IDENTIFIER ON
go

ALTER PROCEDURE [dbo].[OA_ResellerTransactionSel]
	@InputDate SMALLDATETIME = NULL,
	@ResellerID INT = NULL
AS
/*    
 Created : Henry    
 Date : 2012-4-4  
    Task : Get Transaction Rate of a Reseller
    DB  : DB052.bodb_licensee    
     
    Revisions:      
    
*/  

BEGIN  
SET NOCOUNT ON   

DECLARE @YearMonth INT
IF @InputDate IS NULL
	SET @YearMonth=CONVERT(varchar(6),GETDATE(),112)
ELSE
	SET @YearMonth=CONVERT(varchar(6),@InputDate,112)

	SELECT t.ResellerID, r.ResellerName, MinTrans, MaxTrans, t.Rate 
	FROM 
		ResellerTransactionRate t WITH (NOLOCK)
		INNER JOIN Resellers r WITH (NOLOCK) ON t.ResellerID = r.ResellerID
	WHERE 
		@YearMonth BETWEEN FromYearMonth AND ToYearMonth
		AND (isnull(@ResellerID,0)=0 OR (isnull(@ResellerID,0)>0 AND t.ResellerID=@ResellerID))
	
END  
GO
GRANT EXECUTE ON [dbo].[OA_ResellerTransactionSel] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[OA_ResellerTransactionSel] TO [vnteam]



