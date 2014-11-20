USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[LA_PartyListSel]    Script Date: 9/8/2014 4:54:27 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_PartyListSel] 
    -- @FunctinID INT OUTPUT,
	@UserID INT=0,
	@FunctionID INT=0	
AS

/*  
	 Created: 20140814@Florent
	 Task : get List Party of 
	 DB: DB052.bodb_Licensee  
   
	 Revisions:     
	 Params:
	   +UserID : 
		  - 0 get list Party of All user
	   +FunctionID : 
		  - 0 get list Party when config in manage User
			   
*/
SET NOCOUNT ON
BEGIN
Create table #Party 
(
    PartyID INT,    
    PartyGroupID INT    
)
Create table #data
(
    PartyID INT,
    PartyName Nvarchar(100),
    ParentID INT
)
IF (@FunctionID = 0 and @UserID > 0) --get list Party of 1 User
    --get PartyList via User
    BEGIN
	   INSERT INTO #Party
	   SELECT Ci.Fromparty AS PartyID
		   , Ci.Toparty   AS PartyGroupID
		FROM dbo.LA_UserParty Up WITH (NOLOCK) 
			 INNER JOIN dbo.Oas_Chargeinfo Ci WITH (NOLOCK) ON Up.Partyid = Ci.Fromparty AND ci.ProductID = 0	
			 INNER JOIN (
			   SELECT max(FromDate) maxfromdate,FromParty 
				FROM dbo.OAS_ChargeInfo (NOLOCK) WHERE ProductID = 0 AND ToParty in (1,11) GROUP BY FromParty
				) tmp ON ci.FromDate=tmp.maxfromdate AND ci.FromParty=tmp.FromParty		 
		WHERE Userid = @UserID
		  AND Ci.Toparty in ( 11--Boping
						  ,1--OW
						)
	    UNION --get credit	  
	    SELECT p.PartyID
			 ,999 
	    FROM dbo.OAS_Party p WITH (NOLOCK) 
			 INNER JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyID=pd.PartyID
			 INNER JOIN dbo.LA_UserParty UP WITH (NOLOCK) ON p.PartyID=up.PartyID			 
	    WHERE pd.IsDeposit=0 AND UP.UserID = @userID
    END	

IF (@USERID = 0 AND @FunctionID > 0) --get list Party assign to 1 Function
    BEGIN
	    INSERT INTO #Party
	    SELECT Ci.Fromparty AS PartyID
		   , Ci.Toparty   AS PartyGroupID
		FROM dbo.LA_FunctionParty FP WITH (NOLOCK) 
			 INNER JOIN dbo.Oas_Chargeinfo Ci WITH (NOLOCK) ON FP.Partyid = Ci.Fromparty AND ci.ProductID = 0			 
			 INNER JOIN (
			   SELECT max(FromDate) maxfromdate,FromParty 
				FROM dbo.OAS_ChargeInfo (NOLOCK) WHERE ProductID = 0 AND ToParty in (1,11) GROUP BY FromParty
				) tmp ON ci.FromDate=tmp.maxfromdate AND ci.FromParty=tmp.FromParty
		WHERE FP.FunctionID = @FunctionID
		  AND Ci.Toparty in ( 11--Boping
						  ,1--OW
						)
	    UNION --get credit	  
	    SELECT p.PartyID
			 ,999
	    FROM dbo.OAS_Party p WITH (NOLOCK) 
				INNER JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyID=pd.PartyID
				INNER JOIN dbo.LA_FunctionParty FP WITH (NOLOCK) ON p.PartyID=FP.PartyID				
	    WHERE pd.IsDeposit=0 AND FP.FunctionID = @FunctionID
    END

IF (@USERID > 0 AND @FunctionID > 0)--get Party List By User and Function
    BEGIN	   
	   SELECT up.PartyID,Up.UserID,fp.FunctionID ,Up.StatusID
	   INTO #userFunctionParty
	   FROM dbo.LA_UserParty Up WITH (NOLOCK)
		   INNER JOIN dbo.LA_UserFunction UF WITH (NOLOCK) ON up.UserID=uf.UserID --permission of user
		   INNER JOIN dbo.LA_FunctionParty FP WITH (NOLOCK) ON up.PartyID=fp.PartyID and uf.FunctionID=fp.FunctionID --permission of Function - Party
	   WHERE up.UserID = @userID AND fp.FunctionID = @FunctionID

	   --add/remove special Function - Party of User	   	   
	   /* --NOT USE NOW
	   IF EXISTS (SELECT TOP 1 1 FROM dbo.LA_UserSpecialPermission WHERE UserID = @UserID AND FunctionID = @FunctionID)
	   BEGIN
		  --add more with StatusID = 1
		  INSERT INTO #userFunctionParty
		  SELECT PartyID,UserID,FunctionID ,StatusID 
		  FROM dbo.LA_UserSpecialPermission WITH (NOLOCK)
		  WHERE StatusID=1
		  --remove when StatusID = 0
		  DELETE  ufp 
		  FROM #userFunctionParty ufp 
		  INNER JOIN dbo.LA_UserSpecialPermission sp WITH (NOLOCK) ON ufp.UserID=sp.UserID AND ufp.FunctionID=sp.FunctionID AND ufp.PartyID=sp.PartyID
		  WHERE sp.StatusID=0		  
	   END
	   */
	   INSERT INTO #Party
	   SELECT Ci.Fromparty AS PartyID
		   , Ci.Toparty   AS PartyGroupID
		FROM #userFunctionParty A
			 INNER JOIN dbo.Oas_Chargeinfo Ci WITH (NOLOCK) ON a.Partyid = Ci.Fromparty AND ci.ProductID = 0
			 INNER JOIN (
			   SELECT max(FromDate) maxfromdate,FromParty 
				FROM dbo.OAS_ChargeInfo (NOLOCK) WHERE ProductID = 0 AND ToParty in (1,11) GROUP BY FromParty
				) tmp ON ci.FromDate=tmp.maxfromdate AND ci.FromParty=tmp.FromParty
			 --LEFT JOIN dbo.Oas_Party P WITH (NOLOCK) ON a.Partyid = P.Partyid
			 --LEFT JOIN dbo.Oas_Party P1 WITH (NOLOCK) ON Ci.Toparty = P1.Partyid
		WHERE A.Userid = @UserID AND a.FunctionID = @FunctionID
		  AND Ci.Toparty in ( 11--Boping
						  ,1--OW
						)
		UNION 
		SELECT p.PartyID
			 ,999
	    FROM OAS_Party p INNER JOIN OAS_PartyDetail pd ON p.PartyID=pd.PartyID
				      INNER JOIN #userFunctionParty ufp ON p.PartyID=ufp.PartyID				
	    WHERE pd.IsDeposit=0 and ufp.Userid = @UserID AND ufp.FunctionID = @FunctionID
    END
END

IF (@USERID = 0 AND @FunctionID = 0)--getAll Party List 
    BEGIN	   
	    INSERT INTO #Party
	   SELECT Ci.Fromparty AS PartyID
		   , Ci.Toparty   AS PartyGroupID
		FROM OAS_Party FP INNER JOIN Oas_Chargeinfo Ci ON FP.Partyid = Ci.Fromparty AND ci.ProductID = 0	
		INNER JOIN (
			   SELECT max(FromDate) maxfromdate,FromParty 
				FROM dbo.OAS_ChargeInfo (NOLOCK) WHERE ProductID = 0 AND ToParty in (1,11) GROUP BY FromParty
				) tmp ON ci.FromDate=tmp.maxfromdate AND ci.FromParty=tmp.FromParty					 
		WHERE fp.PartyType = 1 and Ci.Toparty in ( 11--Boping
						  ,1--OW
						)
	    UNION --get credit	  
	    SELECT p.PartyID,999
	    FROM OAS_Party p INNER JOIN OAS_PartyDetail pd ON p.PartyID=pd.PartyID				      				      
	    WHERE pd.IsDeposit=0 	   
    END

--parse by ParentID
INSERT INTO #data(PartyID,PartyName,ParentID)
SELECT p.PartyGroupID,
	   CASE 
		  WHEN op.PartyName IS NOT NULL THEN op.PartyName 
		  ELSE 'Credit' 
	   END ,0 as ParentID
    FROM #Party p LEFT JOIN dbo.Oas_Party op WITH (NOLOCK) ON p.PartyGroupID= oP.Partyid			 
    GROUP BY p.PartyGroupID,CASE 
						  WHEN op.PartyName IS NOT NULL THEN op.PartyName 
						  ELSE 'Credit' 
					   END
INSERT INTO #data(PartyID,PartyName,ParentID)
SELECT d.PartyID,
	   CASE op.PartyName 
		  WHEN 'IBC' THEN r.ResellerName
		  WHEN '18bb' THEN r.ResellerName
		  ELSE op.PartyName 
	   END,
a.PartyGroupID 
FROM #Party d INNER JOIN(
    SELECT PartyGroupID
    FROM #Party    
    GROUP BY PartyGroupID
) a on d.PartyGroupID=a.PartyGroupID
LEFT JOIN dbo.Oas_Party op WITH (NOLOCK) ON d.PartyID=op.PartyID AND op.PartyType = 1
LEFT JOIN dbo.LicenseeReseller lr WITH (NOLOCK) ON op.OldRefID=lr.LicenseeID AND d.PartyGroupID = 999
LEFT JOIN dbo.Resellers r WITH (NOLOCK) ON lr.ResellerID=r.ResellerID

SELECT * from #data
ORDER BY ParentID,PartyID

DROP TABLE #Party
DROP TABLE #data
GO
GRANT VIEW DEFINITION ON [dbo].[LA_PartyListSel] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_PartyListSel] TO bodbAdminNet 
