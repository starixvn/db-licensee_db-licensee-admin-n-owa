USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[LA_UserFunctionModify]    Script Date: 9/8/2014 4:58:32 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[LA_UserFunctionModify]
	 @UserID		int
     ,@FunctionIDs	VARCHAR(5500)
	,@Creator		int	
	,@Language	varchar(20) = 'en-us'
	,@LoginIP		varchar(30)=''
	,@ErrCode		int = 0 OUTPUT  
	,@ErrMsg		nvarchar(1000) = '' OUTPUT 
AS
/*  
 * Created: 20140820@Florent
 * Task : Add or modify a user permission of Function(s)
 * DB: DB052.bodb_Licensee  
 *  
 * Revisions:     
*/
SET NOCOUNT ON
DECLARE @startRun datetime  
	,@endRun datetime  
	,@duration int
	,@LogSPData varchar(5000)
	,@LogSPDataOld varchar(5000)
	,@strPermissionFunction Varchar(5500) =''
SET @startRun=GETDATE()
BEGIN
    IF EXISTS(SELECT TOP 1 1 FROM dbo.LA_UserFunction WITH(NOLOCK) WHERE UserID = @UserID)
    BEGIN
	   DECLARE @FunctionListOld varchar(5000)=''
	   SELECT @FunctionListOld = @FunctionListOld + cast(FunctionID as varchar(30)) + ',' 
	   FROM dbo.LA_UserFunction WITH (NOLOCK) 
	   WHERE UserID = @UserID

	   SELECT @strPermissionFunction = @strPermissionFunction + CAST(FunctionID AS VARCHAR(10)) +','
	   FROM dbo.LA_UserFunction WITH (NOLOCK) 
	   WHERE UserID = @UserID 
	   AND FunctionID NOT IN (SELECT FunctionID 
						  FROM dbo.LA_UserFunction WITH (NOLOCK) 
						  WHERE UserID = @Creator)
	   SELECT @strPermissionFunction = SUBSTRING(@strPermissionFunction,0,LEN(@strPermissionFunction))

	   SELECT @LogSPDataOld ='<LA_UserFunctionModify CustID="'+ coalesce(cast(@UserID as varchar(10)),space(1)) + '" ' +  	
		    'FunctionList="'+ coalesce(@FunctionListOld  ,space(1)) + '" ' +  
		    'ModifiedDate="'+ coalesce(cast(ModifyDate as varchar(20)),space(1)) + '" ' +
		    'Modifier="'+ coalesce(cast(modifier as varchar(20)),space(1)) + '" ' +    
		    'Language="'+ coalesce(cast(@Language as varchar(20)),space(1)) + '" ' +  
		    'UserID="'+ coalesce(cast(@Creator as varchar(20)),space(1)) + '" ' + 
		    'IP="'+ coalesce(cast(@LoginIP as varchar(30)),space(1)) + '" />'  
	    FROM  dbo.LA_UserFunction WITH(NOLOCK)
	    WHERE UserID = @UserID
	    --select * from LA_UserFunction
	    DELETE FROM dbo.LA_UserFunction WITH (ROWLOCK) 
	    WHERE UserID = @UserID

	    IF @@Error>0
	    BEGIN
		    SELECT @ErrCode=1, @ErrMsg='Fail to	unassign FunctionID '+@FunctionListOld+' from UserID '+CONVERT(varchar(10),@UserID)
		    RETURN
	    END
    END

    IF @strPermissionFunction != '' 
    BEGIN
	  IF @FunctionIDs !=''
	   SELECT @FunctionIDs = @FunctionIDs + ',' + @strPermissionFunction
       ELSE
	   SELECT @FunctionIDs = @strPermissionFunction
    END

    --check case when user choice only 1 function, must be add parentID for him
    IF EXISTS( SELECT DISTINCT ParentID 
				FROM LA_Function 
				WHERE FunctionID IN( SELECT val FROM bodb02.dbo.strSplit (@FunctionIDs,','))
				AND ParentID NOT IN (SELECT val FROM bodb02.dbo.strSplit (@FunctionIDs,','))
		  )
    BEGIN
	    SELECT @FunctionIDs = @FunctionIDs + ',' +CONVERT(varchar(10),A.ParentID) FROM
		  (
			 SELECT DISTINCT ParentID 
				FROM LA_Function 
				WHERE FunctionID IN( SELECT val FROM bodb02.dbo.strSplit (@FunctionIDs,','))
				AND ParentID NOT IN (SELECT val FROM bodb02.dbo.strSplit (@FunctionIDs,','))
		  ) A
    END   
    
    INSERT INTO dbo.LA_UserFunction (
	UserID,
	FunctionID,
	ModifyDate,
	Modifier,
	StatusID )
    SELECT
	    @UserID,
	    val AS FunctionID,
	    getdate(),
	    @Creator,
	    1 -- default enable
    FROM dbo.strSplit (@FunctionIDs,',')

    IF @@Error>0
    BEGIN
	    SELECT @ErrCode=1, @ErrMsg='Fail to insert data of Function list : '+CONVERT(varchar(10),@FunctionIDs)+' to UserID '+CONVERT(varchar(10),@UserID)
	    RETURN
    END

    SELECT @LogSPData ='<LA_UserFunctionModify CustID="'+ coalesce(cast(@UserID as varchar(10)),space(1)) + '" ' +  	
		    'FunctionList="'+ coalesce(@FunctionIDs  ,space(1)) + '" ' +  
		    'ModifiedDate="'+ coalesce(cast(getdate() as varchar(20)),space(1)) + '" ' +
		    'Modifier="'+ coalesce(cast(@creator as varchar(20)),space(1)) + '" ' +    
		    'Language="'+ coalesce(cast(@Language as varchar(20)),space(1)) + '" ' +  
		    'UserID="'+ coalesce(cast(@Creator as varchar(20)),space(1)) + '" ' + 
		    'IP="'+ coalesce(cast(@LoginIP as varchar(30)),space(1)) + '" />'  

    SET @endRun = getdate()  
    SET @duration  = datediff (millisecond,@startRun,@endRun)   

    EXEC dbo.OA_WriteLog_UserLog_RunSP  
	    @UserID = @Creator,   
	    @CustID = @UserID,
	    @SPName='LA_UserFunctionModify',
	    --@ActionID = 0,  
	    @TrackingValue = @LogSPData,  
	    @TrackingValue2 = @LogSPDataOld,  
	    @duration = @duration
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_UserFunctionModify] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_UserFunctionModify] TO bodbAdminNet 
